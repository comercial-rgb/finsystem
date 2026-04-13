# frozen_string_literal: true
# models/cartao_credito.rb - Model de cartões de crédito (empresarial + pessoal)

module FinSystem
  module Models
    class CartaoCredito
      def self.db
        FinSystem::Database.db
      end

      # ========================================
      # CARTÕES EMPRESARIAIS
      # ========================================
      def self.todos(empresa_id = nil)
        query = db[:cartoes_credito].where(ativo: true)
        query = query.where(empresa_id: empresa_id.to_i) if empresa_id
        query.order(:banco, :apelido).all
      end

      def self.find(id)
        db[:cartoes_credito].where(id: id).first
      end

      def self.criar(params)
        db[:cartoes_credito].insert(
          empresa_id: params[:empresa_id].to_i,
          bandeira: params[:bandeira],
          banco: params[:banco],
          ultimos_digitos: params[:ultimos_digitos],
          apelido: params[:apelido],
          titular: params[:titular],
          limite_total: BigDecimal(params[:limite_total].to_s.gsub('.', '').gsub(',', '.')),
          limite_disponivel: BigDecimal(params[:limite_total].to_s.gsub('.', '').gsub(',', '.')),
          dia_fechamento: params[:dia_fechamento].to_i,
          dia_vencimento: params[:dia_vencimento].to_i,
          moeda: params[:moeda] || 'BRL'
        )
      end

      def self.atualizar(id, params)
        update_data = {}
        %i[bandeira banco ultimos_digitos apelido titular moeda].each do |f|
          update_data[f] = params[f] if params[f]
        end
        update_data[:limite_total] = BigDecimal(params[:limite_total].to_s.gsub('.', '').gsub(',', '.')) if params[:limite_total]
        update_data[:dia_fechamento] = params[:dia_fechamento].to_i if params[:dia_fechamento]
        update_data[:dia_vencimento] = params[:dia_vencimento].to_i if params[:dia_vencimento]
        update_data[:updated_at] = Time.now
        db[:cartoes_credito].where(id: id).update(update_data)
      end

      def self.excluir(id)
        db[:cartoes_credito].where(id: id).update(ativo: false)
      end

      # ========================================
      # FATURAS EMPRESARIAIS
      # ========================================
      def self.fatura_atual(cartao_id)
        cartao = find(cartao_id)
        return nil unless cartao

        hoje = Date.today
        mes = hoje.day >= cartao[:dia_fechamento] ? (hoje >> 1).month : hoje.month
        ano = hoje.day >= cartao[:dia_fechamento] && hoje.month == 12 ? hoje.year + 1 : hoje.year

        fatura = db[:faturas_cartao].where(cartao_id: cartao_id, mes_referencia: mes, ano_referencia: ano).first
        unless fatura
          fatura_id = db[:faturas_cartao].insert(
            cartao_id: cartao_id,
            mes_referencia: mes,
            ano_referencia: ano,
            data_fechamento: Date.new(ano, mes, [cartao[:dia_fechamento], _dias_no_mes(ano, mes)].min),
            data_vencimento: Date.new(ano, mes, [cartao[:dia_vencimento], _dias_no_mes(ano, mes)].min),
            status: 'aberta'
          )
          fatura = db[:faturas_cartao].where(id: fatura_id).first
        end
        fatura
      end

      def self.faturas(cartao_id)
        db[:faturas_cartao].where(cartao_id: cartao_id).order(Sequel.desc(:ano_referencia), Sequel.desc(:mes_referencia)).all
      end

      def self.fatura_find(id)
        db[:faturas_cartao].where(id: id).first
      end

      # Marcar fatura inteira como paga (e todas as despesas associadas)
      def self.pagar_fatura(fatura_id, data_pagamento = nil)
        db.transaction do
          # Marcar todas as despesas pendentes como pagas
          db[:despesas_cartao]
            .where(fatura_id: fatura_id)
            .where(Sequel.~(status: 'cancelada'))
            .update(status: 'paga')

          # Recalcular totais
          _recalcular_fatura(fatura_id)

          # Atualizar status da fatura
          fatura = db[:faturas_cartao].where(id: fatura_id).first
          db[:faturas_cartao].where(id: fatura_id).update(
            status: 'paga',
            valor_pago: fatura[:valor_total]
          )

          # Atualizar limite do cartão
          _atualizar_limite(fatura[:cartao_id])
        end
      end

      def self.faturas_proximas(empresa_id = nil)
        hoje = Date.today
        query = db[:faturas_cartao]
                  .join(:cartoes_credito, Sequel[:cartoes_credito][:id] => Sequel[:faturas_cartao][:cartao_id])
                  .where(Sequel[:faturas_cartao][:status] => %w[aberta fechada])
                  .where { Sequel[:faturas_cartao][:data_vencimento] >= hoje }
        query = query.where(Sequel[:cartoes_credito][:empresa_id] => empresa_id.to_i) if empresa_id
        query
          .select_all(:faturas_cartao)
          .select_append(Sequel[:cartoes_credito][:banco].as(:banco))
          .select_append(Sequel[:cartoes_credito][:bandeira].as(:bandeira))
          .select_append(Sequel[:cartoes_credito][:apelido].as(:cartao_apelido))
          .select_append(Sequel[:cartoes_credito][:ultimos_digitos].as(:ultimos_digitos))
          .order(Sequel[:faturas_cartao][:data_vencimento])
          .limit(10).all
      end

      # ========================================
      # DESPESAS NO CARTÃO EMPRESARIAL
      # ========================================
      def self.criar_despesa_cartao(params)
        total_parcelas = (params[:total_parcelas] || 1).to_i
        total_parcelas = 1 if total_parcelas < 1
        valor_total = BigDecimal(params[:valor_total].to_s.gsub('.', '').gsub(',', '.'))
        valor_parcela = (valor_total / total_parcelas).round(2)

        cartao = find(params[:cartao_id].to_i)
        return nil unless cartao

        ids = []
        db.transaction do
          total_parcelas.times do |i|
            # Calcular em qual fatura cai cada parcela
            data_compra = Date.parse(params[:data_compra])
            mes_fatura = data_compra.day >= cartao[:dia_fechamento] ? (data_compra >> (1 + i)) : (data_compra >> i)

            fatura = _obter_ou_criar_fatura(cartao, mes_fatura.month, mes_fatura.year)

            id = db[:despesas_cartao].insert(
              cartao_id: params[:cartao_id].to_i,
              fatura_id: fatura[:id],
              categoria_id: params[:categoria_id]&.to_i,
              empresa_id: params[:empresa_id].to_i,
              usuario_id: params[:usuario_id].to_i,
              data_compra: data_compra,
              descricao: total_parcelas > 1 ? "#{params[:descricao]} (#{i + 1}/#{total_parcelas})" : params[:descricao],
              valor_total: valor_total,
              valor_parcela: valor_parcela,
              parcela_atual: i + 1,
              total_parcelas: total_parcelas,
              observacoes: params[:observacoes]
            )
            ids << id

            # Atualizar valor da fatura
            _recalcular_fatura(fatura[:id])
          end

          # Atualizar limite disponível
          _atualizar_limite(cartao[:id])
        end
        ids
      end

      def self.despesas_fatura(fatura_id)
        db[:despesas_cartao].where(fatura_id: fatura_id).order(:data_compra).all
      end

      def self.find_despesa(id)
        db[:despesas_cartao].where(id: id).first
      end

      def self.atualizar_despesa_cartao(id, params)
        despesa = find_despesa(id)
        return nil unless despesa

        update_data = {}
        update_data[:descricao] = params[:descricao] if params[:descricao] && !params[:descricao].strip.empty?
        update_data[:valor_parcela] = BigDecimal(params[:valor_parcela].to_s.gsub('.', '').gsub(',', '.')) if params[:valor_parcela] && !params[:valor_parcela].strip.empty?
        update_data[:valor_total] = BigDecimal(params[:valor_total].to_s.gsub('.', '').gsub(',', '.')) if params[:valor_total] && !params[:valor_total].strip.empty?
        update_data[:data_compra] = Date.parse(params[:data_compra]) if params[:data_compra] && !params[:data_compra].strip.empty?
        update_data[:observacoes] = params[:observacoes] if params.key?(:observacoes)
        update_data[:status] = params[:status] if params[:status] && !params[:status].strip.empty?

        return nil if update_data.empty?

        db[:despesas_cartao].where(id: id).update(update_data)

        # Se valor_total mudou e a despesa é parcelada, recalcular parcelas futuras
        if update_data[:valor_total] && despesa[:total_parcelas] > 1
          novo_total = update_data[:valor_total]
          nova_parcela = (novo_total / despesa[:total_parcelas]).round(2)

          # Atualizar todas as parcelas irmãs (mesmo cartão, mesmo valor_total original, mesma data_compra, mesmas parcelas)
          # Identificar irmãs pelo padrão: mesmo cartao_id, total_parcelas e data_compra
          db[:despesas_cartao]
            .where(cartao_id: despesa[:cartao_id], data_compra: despesa[:data_compra], total_parcelas: despesa[:total_parcelas], valor_total: despesa[:valor_total])
            .update(valor_total: novo_total, valor_parcela: nova_parcela)

          # Recalcular todas as faturas afetadas
          faturas_afetadas = db[:despesas_cartao]
            .where(cartao_id: despesa[:cartao_id], data_compra: despesa[:data_compra], total_parcelas: despesa[:total_parcelas], valor_total: novo_total)
            .select(:fatura_id).distinct.all
          faturas_afetadas.each { |f| _recalcular_fatura(f[:fatura_id]) }
        elsif update_data[:valor_parcela] && despesa[:total_parcelas] > 1
          # Se só valor_parcela mudou, atualizar parcelas futuras (parcela_atual > atual)
          nova_parcela = update_data[:valor_parcela]

          db[:despesas_cartao]
            .where(cartao_id: despesa[:cartao_id], data_compra: despesa[:data_compra], total_parcelas: despesa[:total_parcelas], valor_total: despesa[:valor_total])
            .where { parcela_atual >= despesa[:parcela_atual] }
            .update(valor_parcela: nova_parcela)

          # Recalcular novo valor total baseado nas parcelas
          novo_total = db[:despesas_cartao]
            .where(cartao_id: despesa[:cartao_id], data_compra: despesa[:data_compra], total_parcelas: despesa[:total_parcelas])
            .sum(:valor_parcela) || 0
          db[:despesas_cartao]
            .where(cartao_id: despesa[:cartao_id], data_compra: despesa[:data_compra], total_parcelas: despesa[:total_parcelas])
            .update(valor_total: novo_total)

          # Recalcular faturas afetadas
          faturas_afetadas = db[:despesas_cartao]
            .where(cartao_id: despesa[:cartao_id], data_compra: despesa[:data_compra], total_parcelas: despesa[:total_parcelas])
            .select(:fatura_id).distinct.all
          faturas_afetadas.each { |f| _recalcular_fatura(f[:fatura_id]) }
        else
          # Recalcular fatura apenas da despesa editada
          _recalcular_fatura(despesa[:fatura_id])
        end

        # Atualizar limite do cartão
        _atualizar_limite(despesa[:cartao_id])

        id
      end

      def self.excluir_despesa_cartao(id)
        despesa = find_despesa(id)
        return nil unless despesa

        db[:despesas_cartao].where(id: id).delete
        _recalcular_fatura(despesa[:fatura_id])
        _atualizar_limite(despesa[:cartao_id])
        id
      end

      # ========================================
      # CARTÕES PESSOAIS
      # ========================================
      def self.pessoal_todos(usuario_id)
        db[:pessoal_cartoes].where(usuario_id: usuario_id, ativo: true).order(:banco).all
      end

      def self.pessoal_find(id)
        db[:pessoal_cartoes].where(id: id).first
      end

      def self.pessoal_criar(params)
        db[:pessoal_cartoes].insert(
          usuario_id: params[:usuario_id].to_i,
          bandeira: params[:bandeira],
          banco: params[:banco],
          ultimos_digitos: params[:ultimos_digitos],
          apelido: params[:apelido],
          limite_total: BigDecimal(params[:limite_total].to_s.gsub('.', '').gsub(',', '.')),
          dia_fechamento: params[:dia_fechamento].to_i,
          dia_vencimento: params[:dia_vencimento].to_i
        )
      end

      def self.pessoal_excluir(id)
        db[:pessoal_cartoes].where(id: id).update(ativo: false)
      end

      def self.pessoal_fatura_atual(cartao_id)
        cartao = pessoal_find(cartao_id)
        return nil unless cartao

        hoje = Date.today
        mes = hoje.day >= cartao[:dia_fechamento] ? (hoje >> 1).month : hoje.month
        ano = hoje.day >= cartao[:dia_fechamento] && hoje.month == 12 ? hoje.year + 1 : hoje.year

        fatura = db[:pessoal_faturas].where(cartao_id: cartao_id, mes_referencia: mes, ano_referencia: ano).first
        unless fatura
          fatura_id = db[:pessoal_faturas].insert(
            cartao_id: cartao_id,
            mes_referencia: mes,
            ano_referencia: ano,
            data_fechamento: Date.new(ano, mes, [cartao[:dia_fechamento], _dias_no_mes(ano, mes)].min),
            data_vencimento: Date.new(ano, mes, [cartao[:dia_vencimento], _dias_no_mes(ano, mes)].min),
            status: 'aberta'
          )
          fatura = db[:pessoal_faturas].where(id: fatura_id).first
        end
        fatura
      end

      def self.pessoal_faturas(cartao_id)
        db[:pessoal_faturas].where(cartao_id: cartao_id).order(Sequel.desc(:ano_referencia), Sequel.desc(:mes_referencia)).all
      end

      def self.pessoal_faturas_proximas(usuario_id)
        hoje = Date.today
        db[:pessoal_faturas]
          .join(:pessoal_cartoes, Sequel[:pessoal_cartoes][:id] => Sequel[:pessoal_faturas][:cartao_id])
          .where(Sequel[:pessoal_cartoes][:usuario_id] => usuario_id)
          .where(Sequel[:pessoal_faturas][:status] => %w[aberta fechada])
          .where { Sequel[:pessoal_faturas][:data_vencimento] >= hoje }
          .select_all(:pessoal_faturas)
          .select_append(Sequel[:pessoal_cartoes][:banco].as(:banco))
          .select_append(Sequel[:pessoal_cartoes][:bandeira].as(:bandeira))
          .select_append(Sequel[:pessoal_cartoes][:apelido].as(:cartao_apelido))
          .select_append(Sequel[:pessoal_cartoes][:ultimos_digitos].as(:ultimos_digitos))
          .order(Sequel[:pessoal_faturas][:data_vencimento])
          .limit(10).all
      end

      def self.pessoal_criar_despesa(params)
        total_parcelas = (params[:total_parcelas] || 1).to_i
        total_parcelas = 1 if total_parcelas < 1
        valor_total = BigDecimal(params[:valor_total].to_s.gsub('.', '').gsub(',', '.'))
        valor_parcela = (valor_total / total_parcelas).round(2)

        cartao = pessoal_find(params[:cartao_id].to_i)
        return nil unless cartao

        ids = []
        db.transaction do
          total_parcelas.times do |i|
            data_compra = Date.parse(params[:data_compra])
            mes_fatura = data_compra.day >= cartao[:dia_fechamento] ? (data_compra >> (1 + i)) : (data_compra >> i)

            fatura = _obter_ou_criar_fatura_pessoal(cartao, mes_fatura.month, mes_fatura.year)

            id = db[:pessoal_despesas_cartao].insert(
              cartao_id: params[:cartao_id].to_i,
              fatura_id: fatura[:id],
              categoria_id: params[:categoria_id]&.to_i,
              usuario_id: params[:usuario_id].to_i,
              data_compra: data_compra,
              descricao: total_parcelas > 1 ? "#{params[:descricao]} (#{i + 1}/#{total_parcelas})" : params[:descricao],
              valor_total: valor_total,
              valor_parcela: valor_parcela,
              parcela_atual: i + 1,
              total_parcelas: total_parcelas,
              observacoes: params[:observacoes]
            )
            ids << id

            _recalcular_fatura_pessoal(fatura[:id])
          end
        end
        ids
      end

      def self.pessoal_despesas_fatura(fatura_id)
        db[:pessoal_despesas_cartao].where(fatura_id: fatura_id).order(:data_compra).all
      end

      def self.pessoal_find_despesa(id)
        db[:pessoal_despesas_cartao].where(id: id).first
      end

      def self.pessoal_atualizar_despesa(id, params)
        despesa = pessoal_find_despesa(id)
        return nil unless despesa

        update_data = {}
        update_data[:descricao] = params[:descricao] if params[:descricao] && !params[:descricao].strip.empty?
        update_data[:valor_parcela] = BigDecimal(params[:valor_parcela].to_s.gsub('.', '').gsub(',', '.')) if params[:valor_parcela] && !params[:valor_parcela].strip.empty?
        update_data[:valor_total] = BigDecimal(params[:valor_total].to_s.gsub('.', '').gsub(',', '.')) if params[:valor_total] && !params[:valor_total].strip.empty?
        update_data[:data_compra] = Date.parse(params[:data_compra]) if params[:data_compra] && !params[:data_compra].strip.empty?
        update_data[:observacoes] = params[:observacoes] if params.key?(:observacoes)
        update_data[:status] = params[:status] if params[:status] && !params[:status].strip.empty?

        return nil if update_data.empty?

        db[:pessoal_despesas_cartao].where(id: id).update(update_data)
        _recalcular_fatura_pessoal(despesa[:fatura_id])
        id
      end

      def self.pessoal_excluir_despesa(id)
        despesa = pessoal_find_despesa(id)
        return nil unless despesa

        db[:pessoal_despesas_cartao].where(id: id).delete
        _recalcular_fatura_pessoal(despesa[:fatura_id])
        id
      end

      # ========================================
      # RESUMO DE CARTÕES
      # ========================================
      def self.resumo_cartoes(empresa_id = nil)
        cartoes = todos(empresa_id)
        cartoes.map do |c|
          fatura = fatura_atual(c[:id])
          gastos_abertos = db[:despesas_cartao]
            .join(:faturas_cartao, Sequel[:faturas_cartao][:id] => Sequel[:despesas_cartao][:fatura_id])
            .where(Sequel[:despesas_cartao][:cartao_id] => c[:id])
            .where(Sequel[:faturas_cartao][:status] => %w[aberta fechada])
            .sum(Sequel[:despesas_cartao][:valor_parcela]) || 0

          c.merge(
            fatura_atual: fatura,
            gastos_abertos: gastos_abertos,
            limite_usado: c[:limite_total] - (c[:limite_total] - gastos_abertos)
          )
        end
      end

      def self.pessoal_resumo_cartoes(usuario_id)
        cartoes = pessoal_todos(usuario_id)
        cartoes.map do |c|
          fatura = pessoal_fatura_atual(c[:id])
          gastos_abertos = db[:pessoal_despesas_cartao]
            .join(:pessoal_faturas, Sequel[:pessoal_faturas][:id] => Sequel[:pessoal_despesas_cartao][:fatura_id])
            .where(Sequel[:pessoal_despesas_cartao][:cartao_id] => c[:id])
            .where(Sequel[:pessoal_faturas][:status] => %w[aberta fechada])
            .sum(Sequel[:pessoal_despesas_cartao][:valor_parcela]) || 0

          c.merge(
            fatura_atual: fatura,
            gastos_abertos: gastos_abertos
          )
        end
      end

      private

      def self._dias_no_mes(ano, mes)
        Date.new(ano, mes, -1).day
      end

      def self._obter_ou_criar_fatura(cartao, mes, ano)
        fatura = db[:faturas_cartao].where(cartao_id: cartao[:id], mes_referencia: mes, ano_referencia: ano).first
        unless fatura
          fatura_id = db[:faturas_cartao].insert(
            cartao_id: cartao[:id],
            mes_referencia: mes,
            ano_referencia: ano,
            data_fechamento: Date.new(ano, mes, [cartao[:dia_fechamento], _dias_no_mes(ano, mes)].min),
            data_vencimento: Date.new(ano, mes, [cartao[:dia_vencimento], _dias_no_mes(ano, mes)].min),
            status: 'aberta'
          )
          fatura = db[:faturas_cartao].where(id: fatura_id).first
        end
        fatura
      end

      def self._obter_ou_criar_fatura_pessoal(cartao, mes, ano)
        fatura = db[:pessoal_faturas].where(cartao_id: cartao[:id], mes_referencia: mes, ano_referencia: ano).first
        unless fatura
          fatura_id = db[:pessoal_faturas].insert(
            cartao_id: cartao[:id],
            mes_referencia: mes,
            ano_referencia: ano,
            data_fechamento: Date.new(ano, mes, [cartao[:dia_fechamento], _dias_no_mes(ano, mes)].min),
            data_vencimento: Date.new(ano, mes, [cartao[:dia_vencimento], _dias_no_mes(ano, mes)].min),
            status: 'aberta'
          )
          fatura = db[:pessoal_faturas].where(id: fatura_id).first
        end
        fatura
      end

      def self._recalcular_fatura(fatura_id)
        total = db[:despesas_cartao].where(fatura_id: fatura_id).where(Sequel.~(status: 'cancelada')).sum(:valor_parcela) || 0
        pago = db[:despesas_cartao].where(fatura_id: fatura_id, status: 'paga').sum(:valor_parcela) || 0
        db[:faturas_cartao].where(id: fatura_id).update(valor_total: total, valor_pago: pago)
      end

      def self._recalcular_fatura_pessoal(fatura_id)
        total = db[:pessoal_despesas_cartao].where(fatura_id: fatura_id).where(Sequel.~(status: 'cancelada')).sum(:valor_parcela) || 0
        pago = db[:pessoal_despesas_cartao].where(fatura_id: fatura_id, status: 'paga').sum(:valor_parcela) || 0
        db[:pessoal_faturas].where(id: fatura_id).update(valor_total: total, valor_pago: pago)
      end

      def self._atualizar_limite(cartao_id)
        cartao = find(cartao_id)
        gastos = db[:despesas_cartao]
          .join(:faturas_cartao, Sequel[:faturas_cartao][:id] => Sequel[:despesas_cartao][:fatura_id])
          .where(Sequel[:despesas_cartao][:cartao_id] => cartao_id)
          .where(Sequel[:faturas_cartao][:status] => %w[aberta fechada])
          .sum(Sequel[:despesas_cartao][:valor_parcela]) || 0
        db[:cartoes_credito].where(id: cartao_id).update(limite_disponivel: cartao[:limite_total] - gastos)
      end
    end
  end
end
