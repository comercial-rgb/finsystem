# frozen_string_literal: true
# models/pessoal.rb - Model de finanças pessoais

require 'digest'
require 'fileutils'

module FinSystem
  module Models
    class Pessoal
      def self.db
        FinSystem::Database.db
      end

      # ========================================
      # CONTAS BANCÁRIAS PESSOAIS
      # ========================================
      def self.contas_bancarias(usuario_id)
        db[:pessoal_contas_bancarias].where(usuario_id: usuario_id, ativo: true).order(:banco).all
      end

      def self.criar_conta_bancaria(params)
        saldo_str = params[:saldo_inicial].to_s.strip
        saldo_str = '0' if saldo_str.empty?
        db[:pessoal_contas_bancarias].insert(
          usuario_id: params[:usuario_id].to_i,
          banco: params[:banco],
          agencia: params[:agencia],
          conta: params[:conta],
          tipo_conta: params[:tipo_conta] || 'corrente',
          moeda: params[:moeda] || 'BRL',
          saldo_inicial: BigDecimal(saldo_str.gsub('.', '').gsub(',', '.')),
          apelido: params[:apelido]
        )
      end

      def self.atualizar_saldo_conta(id, saldo_str)
        saldo_str = saldo_str.to_s.strip
        saldo_str = '0' if saldo_str.empty?
        db[:pessoal_contas_bancarias].where(id: id).update(
          saldo_inicial: BigDecimal(saldo_str.gsub('.', '').gsub(',', '.'))
        )
      end

      def self.excluir_conta_bancaria(id)
        db[:pessoal_contas_bancarias].where(id: id).update(ativo: false)
      end

      def self.saldo_por_conta_pessoal(usuario_id)
        db[:pessoal_contas_bancarias]
          .where(usuario_id: usuario_id, ativo: true)
          .order(:banco)
          .all
      end

      # ========================================
      # CATEGORIAS PESSOAIS
      # ========================================
      def self.categorias(usuario_id)
        db[:pessoal_categorias].where(usuario_id: usuario_id).order(:tipo, :nome).all
      end

      def self.criar_categoria(params)
        db[:pessoal_categorias].insert(
          usuario_id: params[:usuario_id].to_i,
          nome: params[:nome],
          tipo: params[:tipo],
          cor: params[:cor] || '#6366f1'
        )
      end

      # ========================================
      # MOVIMENTAÇÕES PESSOAIS
      # ========================================
      def self.criar_movimentacao(params)
        db[:pessoal_movimentacoes].insert(
          usuario_id: params[:usuario_id].to_i,
          categoria_id: params[:categoria_id]&.to_i,
          tipo: params[:tipo],
          data_movimentacao: Date.parse(params[:data_movimentacao]),
          descricao: params[:descricao],
          valor: BigDecimal(params[:valor].to_s.gsub('.', '').gsub(',', '.')),
          forma_pagamento: params[:forma_pagamento],
          observacoes: params[:observacoes],
          recorrente: params[:recorrente] == 'true',
          frequencia_recorrencia: params[:frequencia_recorrencia]
        )
      end

      def self.listar_movimentacoes(usuario_id, filtros = {})
        query = db[:pessoal_movimentacoes]
                  .left_join(:pessoal_categorias, Sequel[:pessoal_categorias][:id] => Sequel[:pessoal_movimentacoes][:categoria_id])
                  .where(Sequel[:pessoal_movimentacoes][:usuario_id] => usuario_id)

        if filtros[:mes] && filtros[:ano]
          inicio = Date.new(filtros[:ano].to_i, filtros[:mes].to_i, 1)
          fim = (inicio >> 1) - 1
          query = query.where(Sequel[:pessoal_movimentacoes][:data_movimentacao] => inicio..fim)
        end

        query = query.where(Sequel[:pessoal_movimentacoes][:tipo] => filtros[:tipo]) if filtros[:tipo] && !filtros[:tipo].empty?

        query
          .select_all(:pessoal_movimentacoes)
          .select_append(Sequel[:pessoal_categorias][:nome].as(:categoria_nome))
          .select_append(Sequel[:pessoal_categorias][:cor].as(:categoria_cor))
          .order(Sequel.desc(Sequel[:pessoal_movimentacoes][:data_movimentacao]))
          .all
      end

      def self.find_movimentacao(id)
        db[:pessoal_movimentacoes].where(id: id).first
      end

      def self.atualizar_movimentacao(id, params)
        update_data = {}
        update_data[:categoria_id] = params[:categoria_id]&.to_i if params[:categoria_id]
        update_data[:tipo] = params[:tipo] if params[:tipo]
        update_data[:data_movimentacao] = Date.parse(params[:data_movimentacao]) if params[:data_movimentacao]
        update_data[:descricao] = params[:descricao] if params[:descricao]
        update_data[:valor] = BigDecimal(params[:valor].to_s.gsub('.', '').gsub(',', '.')) if params[:valor]
        update_data[:forma_pagamento] = params[:forma_pagamento] if params[:forma_pagamento]
        update_data[:observacoes] = params[:observacoes] if params.key?(:observacoes)
        update_data[:recorrente] = (params[:recorrente] == 'true') if params.key?(:recorrente)
        update_data[:frequencia_recorrencia] = params[:frequencia_recorrencia] if params.key?(:frequencia_recorrencia)
        db[:pessoal_movimentacoes].where(id: id).update(update_data)
      end

      def self.excluir_movimentacao(id)
        # Excluir comprovantes associados
        comprovantes = db[:pessoal_comprovantes].where(movimentacao_id: id).all
        comprovantes.each do |comp|
          begin
            File.delete(comp[:caminho_arquivo]) if comp[:caminho_arquivo] && File.exist?(comp[:caminho_arquivo])
          rescue Errno::ENOENT
            # Arquivo já removido (filesystem efêmero)
          end
        end
        db[:pessoal_comprovantes].where(movimentacao_id: id).delete
        db[:pessoal_movimentacoes].where(id: id).delete
      end

      # ========================================
      # COMPROVANTES PESSOAIS
      # ========================================
      def self.salvar_comprovante(movimentacao_id, arquivo)
        return nil unless arquivo && arquivo[:tempfile]

        tipo = arquivo[:type]
        return { error: 'Tipo de arquivo não permitido' } unless Config::ALLOWED_FILE_TYPES.include?(tipo)

        size = arquivo[:tempfile].size
        return { error: 'Arquivo excede 10MB' } if size > Config::MAX_UPLOAD_SIZE

        ext = File.extname(arquivo[:filename])
        nome_unico = "pessoal_#{Time.now.strftime('%Y%m%d_%H%M%S')}_#{SecureRandom.hex(8)}#{ext}"

        dir = File.join(Config::UPLOAD_PESSOAL_DIR, Date.today.strftime('%Y/%m'))
        FileUtils.mkdir_p(dir)

        caminho = File.join(dir, nome_unico)
        File.open(caminho, 'wb') { |f| f.write(arquivo[:tempfile].read) }

        hash = Digest::SHA256.file(caminho).hexdigest

        db[:pessoal_comprovantes].insert(
          movimentacao_id: movimentacao_id,
          nome_arquivo: nome_unico,
          nome_original: arquivo[:filename],
          caminho_arquivo: caminho,
          hash_arquivo: hash
        )
      end

      def self.comprovantes_por_movimentacao(movimentacao_id)
        db[:pessoal_comprovantes].where(movimentacao_id: movimentacao_id).order(:created_at).all
      end

      def self.excluir_comprovante(id)
        comp = db[:pessoal_comprovantes].where(id: id).first
        if comp
          begin
            File.delete(comp[:caminho_arquivo]) if comp[:caminho_arquivo] && File.exist?(comp[:caminho_arquivo])
          rescue Errno::ENOENT; end
          db[:pessoal_comprovantes].where(id: id).delete
          comp[:movimentacao_id]
        end
      end

      # ========================================
      # RESUMO PESSOAL
      # ========================================
      def self.resumo(usuario_id, mes, ano)
        inicio = Date.new(ano.to_i, mes.to_i, 1)
        fim = (inicio >> 1) - 1

        base = db[:pessoal_movimentacoes]
                 .where(Sequel[:pessoal_movimentacoes][:usuario_id] => usuario_id, Sequel[:pessoal_movimentacoes][:data_movimentacao] => inicio..fim)

        receitas = base.where(tipo: 'receita').sum(:valor) || 0
        despesas = base.where(tipo: 'despesa').sum(:valor) || 0
        investimentos = base.where(tipo: 'investimento').sum(:valor) || 0

        {
          receitas: receitas,
          despesas: despesas,
          investimentos: investimentos,
          saldo: receitas - despesas - investimentos,
          disponivel_investir: receitas - despesas,
          por_categoria: base
            .left_join(:pessoal_categorias, Sequel[:pessoal_categorias][:id] => Sequel[:pessoal_movimentacoes][:categoria_id])
            .group(Sequel[:pessoal_categorias][:nome], Sequel[:pessoal_categorias][:cor], Sequel[:pessoal_movimentacoes][:tipo])
            .select(
              Sequel[:pessoal_categorias][:nome].as(:categoria),
              Sequel[:pessoal_categorias][:cor].as(:cor),
              Sequel[:pessoal_movimentacoes][:tipo],
              Sequel.function(:sum, Sequel[:pessoal_movimentacoes][:valor]).as(:total)
            ).all
        }
      end
    end
  end
end
