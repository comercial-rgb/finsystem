# frozen_string_literal: true
# models/movimentacao.rb - Model principal de movimentações financeiras

module FinSystem
  module Models
    class Movimentacao
      def self.db
        FinSystem::Database.db
      end

      def self.table
        db[:movimentacoes]
      end

      # ========================================
      # CRUD
      # ========================================

      def self.criar(params)
        # Determinar tipo de cobrança e parcelas
        tipo_cobranca = params[:tipo_cobranca] || 'unica'
        total_parcelas = (params[:total_parcelas] || 1).to_i
        total_parcelas = 1 if total_parcelas < 1
        data_mov = Date.parse(params[:data_movimentacao])

        # Para cobrança única, criar uma movimentação normal
        if tipo_cobranca == 'unica' || (tipo_cobranca == 'parcelada' && total_parcelas <= 1)
          return _inserir_movimentacao(params, data_mov, tipo_cobranca, 1, 1, data_mov)
        end

        # Para parceladas, criar múltiplas
        if tipo_cobranca == 'parcelada'
          valor_bruto_total = BigDecimal(params[:valor_bruto].to_s.gsub('.', '').gsub(',', '.'))
          valor_parcela = (valor_bruto_total / total_parcelas).round(2)
          ids = []
          primeiro_id = nil

          db.transaction do
            total_parcelas.times do |i|
              data_parcela = data_mov >> i
              p = params.dup
              p[:valor_bruto] = valor_parcela.to_s
              p[:descricao] = "#{params[:descricao]} (#{i + 1}/#{total_parcelas})"
              id = _inserir_movimentacao(p, data_parcela, 'parcelada', i + 1, total_parcelas, data_parcela)
              primeiro_id ||= id
              ids << id
            end
            # Vincular ao pai
            ids.each { |id| table.where(id: id).update(recorrencia_pai_id: primeiro_id) }
          end
          return primeiro_id
        end

        # Para recorrentes, criar apenas a primeira e agendar
        if tipo_cobranca == 'recorrente'
          dia_venc = (params[:dia_vencimento_recorrente] || data_mov.day).to_i
          prox_mes = data_mov >> 1
          prox_venc = Date.new(prox_mes.year, prox_mes.month, [dia_venc, Date.new(prox_mes.year, prox_mes.month, -1).day].min)
          return _inserir_movimentacao(params, data_mov, 'recorrente', 1, 1, prox_venc, dia_venc)
        end

        # Fallback
        _inserir_movimentacao(params, data_mov, tipo_cobranca, 1, 1, data_mov)
      end

      def self._inserir_movimentacao(params, data_mov, tipo_cobranca, parcela_atual, total_parcelas, data_prox_venc, dia_venc = nil)
        data = {
          empresa_id: params[:empresa_id].to_i,
          conta_bancaria_id: params[:conta_bancaria_id].to_i,
          categoria_id: params[:categoria_id]&.to_i,
          cliente_id: params[:cliente_id]&.to_i,
          fornecedor_id: params[:fornecedor_id]&.to_i,
          usuario_id: params[:usuario_id].to_i,
          tipo: params[:tipo],
          data_movimentacao: data_mov,
          data_competencia: params[:data_competencia] ? Date.parse(params[:data_competencia]) : data_mov,
          descricao: params[:descricao],
          valor_bruto: BigDecimal(params[:valor_bruto].to_s.gsub('.', '').gsub(',', '.')),
          valor_liquido: params[:valor_liquido].to_s.strip.empty? ? nil : BigDecimal(params[:valor_liquido].to_s.gsub('.', '').gsub(',', '.')),
          lucro: params[:lucro].to_s.strip.empty? ? BigDecimal('0') : BigDecimal(params[:lucro].to_s.gsub('.', '').gsub(',', '.')),
          tipo_operacao: params[:tipo_operacao],
          numero_documento: params[:numero_documento],
          status: params[:status] || 'confirmado',
          forma_pagamento: params[:forma_pagamento],
          observacoes: params[:observacoes],
          is_antecipacao: params[:is_antecipacao] == 'true' || params[:is_antecipacao] == true,
          valor_antecipado: params[:valor_antecipado] ? BigDecimal(params[:valor_antecipado].to_s.gsub('.', '').gsub(',', '.')) : nil,
          taxa_antecipacao: params[:taxa_antecipacao] ? BigDecimal(params[:taxa_antecipacao].to_s.gsub('.', '').gsub(',', '.')) : nil,
          valor_original_faturamento: params[:valor_original_faturamento] ? BigDecimal(params[:valor_original_faturamento].to_s.gsub('.', '').gsub(',', '.')) : nil,
          referencia_banco: params[:referencia_banco],
          tipo_cobranca: tipo_cobranca,
          total_parcelas: total_parcelas,
          parcela_atual: parcela_atual,
          dia_vencimento_recorrente: dia_venc,
          data_proximo_vencimento: data_prox_venc,
          pago: (params[:status] == 'confirmado')
        }

        # Calcular valor líquido se não informado
        data[:valor_liquido] ||= data[:valor_bruto]

        id = table.insert(data)

        # Atualizar saldo da conta se status confirmado
        if data[:status] == 'confirmado'
          atualizar_saldo_conta(data[:conta_bancaria_id])
          registrar_historico_saldo(data[:conta_bancaria_id], data_mov, 'movimentacao', id, data[:descricao])
        end

        id
      end

      # Criar antecipação (gera 2 movimentações: despesa do valor antecipado + receita da taxa)
      def self.criar_antecipacao(params)
        db.transaction do
          # 1. Despesa: valor antecipado ao fornecedor (sai do caixa)
          criar(
            empresa_id: params[:empresa_id],
            conta_bancaria_id: params[:conta_bancaria_id],
            categoria_id: params[:categoria_despesa_id],
            fornecedor_id: params[:fornecedor_id],
            usuario_id: params[:usuario_id],
            tipo: 'despesa',
            data_movimentacao: params[:data_movimentacao],
            descricao: "Antecipação para #{params[:fornecedor_nome]} - Valor enviado",
            valor_bruto: params[:valor_antecipado],
            tipo_operacao: 'antecipacao',
            is_antecipacao: true,
            valor_antecipado: params[:valor_antecipado],
            valor_original_faturamento: params[:valor_original],
            taxa_antecipacao: params[:taxa],
            forma_pagamento: params[:forma_pagamento],
            status: 'confirmado',
            observacoes: params[:observacoes]
          )

          # 2. Receita: taxa/lucro da antecipação
          criar(
            empresa_id: params[:empresa_id],
            conta_bancaria_id: params[:conta_bancaria_id],
            categoria_id: params[:categoria_receita_id],
            fornecedor_id: params[:fornecedor_id],
            usuario_id: params[:usuario_id],
            tipo: 'receita',
            data_movimentacao: params[:data_movimentacao],
            descricao: "Lucro antecipação - #{params[:fornecedor_nome]}",
            valor_bruto: params[:taxa],
            lucro: params[:taxa],
            tipo_operacao: 'antecipacao',
            is_antecipacao: true,
            forma_pagamento: params[:forma_pagamento],
            status: 'confirmado',
            observacoes: "Taxa sobre antecipação de R$ #{params[:valor_original]}"
          )
        end
      end

      def self.find(id)
        table.where(id: id).first
      end

      def self.atualizar(id, params)
        mov = find(id)
        update_data = {}
        %i[categoria_id cliente_id fornecedor_id conta_bancaria_id tipo data_movimentacao
           descricao valor_bruto valor_liquido lucro tipo_operacao numero_documento
           status forma_pagamento observacoes conciliado referencia_banco].each do |field|
          if params[field]
            val = params[field]
            val = BigDecimal(val.to_s.gsub('.', '').gsub(',', '.')) if %i[valor_bruto valor_liquido lucro].include?(field)
            val = Date.parse(val) if field == :data_movimentacao
            val = (val == 'true') if field == :conciliado
            update_data[field] = val
          end
        end
        update_data[:updated_at] = Time.now
        table.where(id: id).update(update_data)

        # Recalcular saldo das contas afetadas
        if mov
          atualizar_saldo_conta(mov[:conta_bancaria_id])
          # Se a conta mudou, atualizar a nova conta também
          nova_conta = update_data[:conta_bancaria_id]
          if nova_conta && nova_conta.to_i != mov[:conta_bancaria_id]
            atualizar_saldo_conta(nova_conta.to_i)
          end
        end
      end

      def self.excluir(id)
        mov = find(id)
        table.where(id: id).delete

        # Recalcular saldo da conta
        atualizar_saldo_conta(mov[:conta_bancaria_id]) if mov
      end

      # ========================================
      # CONSULTAS E RELATÓRIOS
      # ========================================

      # Listar movimentações com filtros
      def self.listar(filtros = {})
        query = table
                  .left_join(:empresas, id: :empresa_id)
                  .left_join(:contas_bancarias, Sequel[:contas_bancarias][:id] => Sequel[:movimentacoes][:conta_bancaria_id])
                  .left_join(:categorias, Sequel[:categorias][:id] => Sequel[:movimentacoes][:categoria_id])
                  .left_join(:clientes, Sequel[:clientes][:id] => Sequel[:movimentacoes][:cliente_id])
                  .left_join(:fornecedores, Sequel[:fornecedores][:id] => Sequel[:movimentacoes][:fornecedor_id])

        # Filtros
        query = query.where(Sequel[:movimentacoes][:empresa_id] => filtros[:empresa_id].to_i) if filtros[:empresa_id]
        query = query.where(Sequel[:movimentacoes][:tipo] => filtros[:tipo]) if filtros[:tipo] && !filtros[:tipo].empty?
        query = query.where(Sequel[:movimentacoes][:conta_bancaria_id] => filtros[:conta_bancaria_id].to_i) if filtros[:conta_bancaria_id]
        query = query.where(Sequel[:movimentacoes][:status] => filtros[:status]) if filtros[:status] && !filtros[:status].empty?

        if filtros[:mes] && filtros[:ano]
          inicio = Date.new(filtros[:ano].to_i, filtros[:mes].to_i, 1)
          fim = (inicio >> 1) - 1
          query = query.where(Sequel[:movimentacoes][:data_movimentacao] => inicio..fim)
        elsif filtros[:data_inicio] && filtros[:data_fim]
          query = query.where(Sequel[:movimentacoes][:data_movimentacao] => Date.parse(filtros[:data_inicio])..Date.parse(filtros[:data_fim]))
        end

        query = query.where(Sequel.like(Sequel[:movimentacoes][:descricao], "%#{filtros[:busca]}%")) if filtros[:busca] && !filtros[:busca].empty?

        query
          .select_all(:movimentacoes)
          .select_append(Sequel[:empresas][:nome_fantasia].as(:empresa_nome))
          .select_append(Sequel[:contas_bancarias][:banco].as(:banco_nome))
          .select_append(Sequel[:contas_bancarias][:apelido].as(:conta_apelido))
          .select_append(Sequel[:categorias][:nome].as(:categoria_nome))
          .select_append(Sequel[:categorias][:cor].as(:categoria_cor))
          .select_append(Sequel[:clientes][:nome].as(:cliente_nome))
          .select_append(Sequel[:fornecedores][:nome].as(:fornecedor_nome))
          .order(Sequel.desc(Sequel[:movimentacoes][:data_movimentacao]), Sequel.desc(Sequel[:movimentacoes][:id]))
          .all
      end

      # Resumo mensal por empresa
      def self.resumo_mensal(empresa_id, mes, ano)
        inicio = Date.new(ano.to_i, mes.to_i, 1)
        fim = (inicio >> 1) - 1

        # Qualificar colunas com nome da tabela para evitar PG::AmbiguousColumn em JOINs
        base = table.where(
          Sequel[:movimentacoes][:empresa_id] => empresa_id.to_i,
          Sequel[:movimentacoes][:data_movimentacao] => inicio..fim,
          Sequel[:movimentacoes][:status] => %w[confirmado conciliado pendente]
        )

        {
          total_receitas: base.where(tipo: 'receita').sum(:valor_bruto) || 0,
          total_despesas: base.where(tipo: 'despesa').sum(:valor_bruto) || 0,
          lucro_total: base.sum(:lucro) || 0,
          total_antecipacoes: base.where(is_antecipacao: true, tipo: 'despesa').sum(:valor_bruto) || 0,
          lucro_antecipacoes: base.where(is_antecipacao: true, tipo: 'receita').sum(:valor_bruto) || 0,
          qtd_movimentacoes: base.count,
          por_categoria: base
            .left_join(:categorias, Sequel[:categorias][:id] => Sequel[:movimentacoes][:categoria_id])
            .group(Sequel[:categorias][:nome], Sequel[:categorias][:cor], Sequel[:movimentacoes][:tipo])
            .select(
              Sequel[:categorias][:nome].as(:categoria),
              Sequel[:categorias][:cor].as(:cor),
              Sequel[:movimentacoes][:tipo],
              Sequel.function(:sum, Sequel[:movimentacoes][:valor_bruto]).as(:total),
              Sequel.function(:count, Sequel[:movimentacoes][:id]).as(:qtd)
            ).all,
          por_banco: base
            .left_join(:contas_bancarias, Sequel[:contas_bancarias][:id] => Sequel[:movimentacoes][:conta_bancaria_id])
            .group(Sequel[:contas_bancarias][:banco])
            .select(
              Sequel[:contas_bancarias][:banco].as(:banco),
              Sequel.function(:sum, Sequel.case({ 'receita' => Sequel[:movimentacoes][:valor_bruto] }, 0, Sequel[:movimentacoes][:tipo])).as(:entradas),
              Sequel.function(:sum, Sequel.case({ 'despesa' => Sequel[:movimentacoes][:valor_bruto] }, 0, Sequel[:movimentacoes][:tipo])).as(:saidas)
            ).all
        }
      end

      # Saldo por conta bancária (inclui nome da empresa)
      def self.saldo_por_conta(empresa_id = nil)
        query = db[:contas_bancarias]
                  .left_join(:empresas, Sequel[:empresas][:id] => Sequel[:contas_bancarias][:empresa_id])
        query = query.where(Sequel[:contas_bancarias][:empresa_id] => empresa_id.to_i) if empresa_id && !empresa_id.to_s.empty?

        query.left_join(:movimentacoes,
                        Sequel[:movimentacoes][:conta_bancaria_id] => Sequel[:contas_bancarias][:id],
                        Sequel[:movimentacoes][:status] => 'confirmado')
             .group(Sequel[:contas_bancarias][:id], Sequel[:contas_bancarias][:banco],
                    Sequel[:contas_bancarias][:apelido], Sequel[:contas_bancarias][:saldo_inicial],
                    Sequel[:contas_bancarias][:moeda], Sequel[:empresas][:nome_fantasia])
             .select(
               Sequel[:contas_bancarias][:id],
               Sequel[:contas_bancarias][:banco],
               Sequel[:contas_bancarias][:apelido],
               Sequel[:contas_bancarias][:saldo_inicial],
               Sequel[:contas_bancarias][:moeda],
               Sequel[:empresas][:nome_fantasia].as(:empresa_nome),
               Sequel.function(:sum, Sequel.case(
                 { 'receita' => Sequel[:movimentacoes][:valor_bruto] }, 0,
                 Sequel[:movimentacoes][:tipo]
               )).as(:total_entradas),
               Sequel.function(:sum, Sequel.case(
                 { 'despesa' => Sequel[:movimentacoes][:valor_bruto] }, 0,
                 Sequel[:movimentacoes][:tipo]
               )).as(:total_saidas)
             ).all
      end

      # Despesas pendentes de pagamento (lembretes)
      def self.despesas_pendentes_pagamento
        hoje = Date.today
        table.where(tipo: 'despesa', pago: false)
             .where { data_proximo_vencimento <= (hoje + 30) }
             .where(Sequel.lit('tipo_cobranca IS NOT NULL AND tipo_cobranca != ?', 'unica'))
             .left_join(:empresas, Sequel[:empresas][:id] => Sequel[:movimentacoes][:empresa_id])
             .select_all(:movimentacoes)
             .select_append(Sequel[:empresas][:nome_fantasia].as(:empresa_nome))
             .order(Sequel[:movimentacoes][:data_proximo_vencimento])
             .all
      end

      # Todas despesas não pagas (recorrentes + parceladas + únicas pendentes)
      def self.lembretes_pagamento
        hoje = Date.today
        table.where(tipo: 'despesa')
             .where(Sequel.|(Sequel.&(pago: false), { status: 'pendente' }))
             .where { Sequel[:movimentacoes][:data_proximo_vencimento] <= (hoje + 30) }
             .left_join(:empresas, Sequel[:empresas][:id] => Sequel[:movimentacoes][:empresa_id])
             .left_join(:contas_bancarias, Sequel[:contas_bancarias][:id] => Sequel[:movimentacoes][:conta_bancaria_id])
             .select_all(:movimentacoes)
             .select_append(Sequel[:empresas][:nome_fantasia].as(:empresa_nome))
             .select_append(Sequel[:contas_bancarias][:banco].as(:banco_nome))
             .order(Sequel[:movimentacoes][:data_proximo_vencimento])
             .all
      end

      # Conciliar movimentação
      def self.conciliar(id, referencia)
        table.where(id: id).update(
          conciliado: true,
          status: 'conciliado',
          data_conciliacao: Date.today,
          referencia_banco: referencia,
          updated_at: Time.now
        )
      end

      # ========================================
      # TRANSFERÊNCIA ENTRE CONTAS
      # ========================================
      def self.criar_transferencia(params)
        valor = BigDecimal(params[:valor].to_s.gsub('.', '').gsub(',', '.'))
        data = Date.parse(params[:data_transferencia])
        conta_origem_id = params[:conta_origem_id].to_i
        conta_destino_id = params[:conta_destino_id].to_i
        usuario_id = params[:usuario_id].to_i
        descricao = params[:descricao] || 'Transferência entre contas'

        conta_origem = db[:contas_bancarias].where(id: conta_origem_id).first
        conta_destino = db[:contas_bancarias].where(id: conta_destino_id).first
        raise 'Conta de origem não encontrada' unless conta_origem
        raise 'Conta de destino não encontrada' unless conta_destino
        raise 'Conta de origem e destino devem ser diferentes' if conta_origem_id == conta_destino_id

        empresa_origem = db[:empresas].where(id: conta_origem[:empresa_id]).first
        empresa_destino = db[:empresas].where(id: conta_destino[:empresa_id]).first

        db.transaction do
          # 1. Criar movimentação de saída na conta origem
          saida_id = table.insert(
            empresa_id: conta_origem[:empresa_id],
            conta_bancaria_id: conta_origem_id,
            usuario_id: usuario_id,
            tipo: 'despesa',
            data_movimentacao: data,
            data_competencia: data,
            descricao: "Transferência para #{conta_destino[:banco]} (#{conta_destino[:apelido]}) - #{empresa_destino[:nome_fantasia]}",
            valor_bruto: valor,
            valor_liquido: valor,
            lucro: 0,
            tipo_operacao: 'transferencia',
            status: 'confirmado',
            forma_pagamento: 'ted',
            pago: true,
            tipo_cobranca: 'unica',
            observacoes: descricao
          )

          # 2. Criar movimentação de entrada na conta destino
          entrada_id = table.insert(
            empresa_id: conta_destino[:empresa_id],
            conta_bancaria_id: conta_destino_id,
            usuario_id: usuario_id,
            tipo: 'receita',
            data_movimentacao: data,
            data_competencia: data,
            descricao: "Transferência de #{conta_origem[:banco]} (#{conta_origem[:apelido]}) - #{empresa_origem[:nome_fantasia]}",
            valor_bruto: valor,
            valor_liquido: valor,
            lucro: 0,
            tipo_operacao: 'transferencia',
            status: 'confirmado',
            forma_pagamento: 'ted',
            pago: true,
            tipo_cobranca: 'unica',
            observacoes: descricao
          )

          # 3. Registrar transferência
          transf_id = db[:transferencias].insert(
            conta_origem_id: conta_origem_id,
            conta_destino_id: conta_destino_id,
            usuario_id: usuario_id,
            valor: valor,
            data_transferencia: data,
            descricao: descricao,
            observacoes: params[:observacoes],
            movimentacao_saida_id: saida_id,
            movimentacao_entrada_id: entrada_id
          )

          # 4. Atualizar saldos
          atualizar_saldo_conta(conta_origem_id)
          atualizar_saldo_conta(conta_destino_id)

          # 5. Registrar histórico
          registrar_historico_saldo(conta_origem_id, data, 'transferencia', transf_id, "Saída: #{descricao}")
          registrar_historico_saldo(conta_destino_id, data, 'transferencia', transf_id, "Entrada: #{descricao}")

          transf_id
        end
      end

      # ========================================
      # ATUALIZAÇÃO DE SALDOS
      # ========================================
      def self.atualizar_saldo_conta(conta_id)
        conta = db[:contas_bancarias].where(id: conta_id).first
        return unless conta

        saldo_inicial = conta[:saldo_inicial] || 0
        entradas = table.where(conta_bancaria_id: conta_id, status: 'confirmado', tipo: 'receita').sum(:valor_bruto) || 0
        saidas = table.where(conta_bancaria_id: conta_id, status: 'confirmado', tipo: 'despesa').sum(:valor_bruto) || 0

        saldo_atual = saldo_inicial + entradas - saidas
        db[:contas_bancarias].where(id: conta_id).update(saldo_atual: saldo_atual)
        saldo_atual
      end

      def self.registrar_historico_saldo(conta_id, data, tipo_evento, evento_id, descricao = nil)
        saldo = db[:contas_bancarias].where(id: conta_id).get(:saldo_atual) || 0
        db[:historico_saldos].insert(
          conta_bancaria_id: conta_id,
          data_referencia: data,
          saldo: saldo,
          tipo_evento: tipo_evento,
          evento_id: evento_id,
          descricao: descricao
        )
      end

      # Listar transferências
      def self.transferencias(filtros = {})
        query = db[:transferencias]
                  .join(Sequel[:contas_bancarias].as(:co), Sequel[:co][:id] => Sequel[:transferencias][:conta_origem_id])
                  .join(Sequel[:contas_bancarias].as(:cd), Sequel[:cd][:id] => Sequel[:transferencias][:conta_destino_id])
                  .left_join(Sequel[:empresas].as(:eo), Sequel[:eo][:id] => Sequel[:co][:empresa_id])
                  .left_join(Sequel[:empresas].as(:ed), Sequel[:ed][:id] => Sequel[:cd][:empresa_id])

        query
          .select_all(:transferencias)
          .select_append(Sequel[:co][:banco].as(:banco_origem))
          .select_append(Sequel[:co][:apelido].as(:apelido_origem))
          .select_append(Sequel[:cd][:banco].as(:banco_destino))
          .select_append(Sequel[:cd][:apelido].as(:apelido_destino))
          .select_append(Sequel[:eo][:nome_fantasia].as(:empresa_origem))
          .select_append(Sequel[:ed][:nome_fantasia].as(:empresa_destino))
          .order(Sequel.desc(Sequel[:transferencias][:data_transferencia]))
          .limit(50)
          .all
      end
    end
  end
end
