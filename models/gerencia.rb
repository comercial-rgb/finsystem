# frozen_string_literal: true
# models/gerencia.rb - Models para o módulo de Gerência

module FinSystem
  module Models
    module Gerencia
      # ========================================
      # FINANCEIRO - RECEBIMENTOS
      # ========================================
      def self.listar_recebimentos(filtros = {})
        db = Database.db
        query = db[:gerencia_recebimentos].order(Sequel.desc(:created_at))
        query = query.where(frente: filtros[:frente]) if filtros[:frente] && !filtros[:frente].empty?
        query = query.where(Sequel.extract(:month, :data_recebimento) => filtros[:mes].to_i) if filtros[:mes]
        query = query.where(Sequel.extract(:year, :data_recebimento) => filtros[:ano].to_i) if filtros[:ano]
        query.all
      end

      def self.criar_recebimento(params)
        db = Database.db
        db[:gerencia_recebimentos].insert(
          frente: params[:frente],
          descricao: params[:descricao],
          valor: parse_valor(params[:valor]),
          data_recebimento: params[:data_recebimento],
          observacoes: params[:observacoes],
          created_at: Time.now
        )
      end

      def self.excluir_recebimento(id)
        Database.db[:gerencia_recebimentos].where(id: id.to_i).delete
      end

      # ========================================
      # NOTAS FISCAIS EM ABERTO - CLIENTES
      # ========================================
      def self.listar_nf_clientes(filtros = {})
        db = Database.db
        query = db[:gerencia_nf_clientes].order(Sequel.desc(:data_vencimento))
        query = query.where(status: filtros[:status]) if filtros[:status] && !filtros[:status].empty?
        query.all
      end

      def self.criar_nf_cliente(params)
        db = Database.db
        db[:gerencia_nf_clientes].insert(
          nome_cliente: params[:nome_cliente],
          centro_custo: params[:centro_custo],
          periodo_apurado: params[:periodo_apurado],
          data_vencimento: params[:data_vencimento],
          valor_bruto: parse_valor(params[:valor_bruto]),
          valor_liquido: parse_valor(params[:valor_liquido]),
          status: params[:status] || 'aberta',
          created_at: Time.now
        )
      end

      def self.atualizar_nf_cliente(id, params)
        db = Database.db
        dados = {
          nome_cliente: params[:nome_cliente],
          centro_custo: params[:centro_custo],
          periodo_apurado: params[:periodo_apurado],
          data_vencimento: params[:data_vencimento],
          valor_bruto: parse_valor(params[:valor_bruto]),
          valor_liquido: parse_valor(params[:valor_liquido]),
          status: params[:status]
        }.compact
        db[:gerencia_nf_clientes].where(id: id.to_i).update(dados)
      end

      def self.excluir_nf_cliente(id)
        Database.db[:gerencia_nf_clientes].where(id: id.to_i).delete
      end

      # ========================================
      # NOTAS FISCAIS EM ABERTO - FORNECEDORES
      # ========================================
      def self.listar_nf_fornecedores(filtros = {})
        db = Database.db
        query = db[:gerencia_nf_fornecedores].order(Sequel.desc(:vencimento))
        query = query.where(status: filtros[:status]) if filtros[:status] && !filtros[:status].empty?
        query.all
      end

      def self.criar_nf_fornecedor(params)
        db = Database.db
        db[:gerencia_nf_fornecedores].insert(
          numero_fatura: params[:numero_fatura],
          cliente_centro_custo: params[:cliente_centro_custo],
          periodo_apurado: params[:periodo_apurado],
          vencimento: params[:vencimento],
          valor_bruto: parse_valor(params[:valor_bruto]),
          valor_liquido: parse_valor(params[:valor_liquido]),
          status: params[:status] || 'aberta',
          created_at: Time.now
        )
      end

      def self.atualizar_nf_fornecedor(id, params)
        db = Database.db
        dados = {
          numero_fatura: params[:numero_fatura],
          cliente_centro_custo: params[:cliente_centro_custo],
          periodo_apurado: params[:periodo_apurado],
          vencimento: params[:vencimento],
          valor_bruto: parse_valor(params[:valor_bruto]),
          valor_liquido: parse_valor(params[:valor_liquido]),
          status: params[:status]
        }.compact
        db[:gerencia_nf_fornecedores].where(id: id.to_i).update(dados)
      end

      def self.excluir_nf_fornecedor(id)
        Database.db[:gerencia_nf_fornecedores].where(id: id.to_i).delete
      end

      # ========================================
      # NOTAS FISCAIS PAGAS
      # ========================================
      def self.listar_nf_pagas(filtros = {})
        db = Database.db
        query = db[:gerencia_nf_pagas].order(Sequel.desc(:data_vencimento))
        query.all
      end

      def self.criar_nf_paga(params)
        db = Database.db
        db[:gerencia_nf_pagas].insert(
          nome_cliente: params[:nome_cliente],
          centro_custo: params[:centro_custo],
          periodo_apurado: params[:periodo_apurado],
          data_vencimento: params[:data_vencimento],
          valor_bruto: parse_valor(params[:valor_bruto]),
          valor_liquido: parse_valor(params[:valor_liquido]),
          created_at: Time.now
        )
      end

      def self.excluir_nf_paga(id)
        Database.db[:gerencia_nf_pagas].where(id: id.to_i).delete
      end

      # ========================================
      # CREDENCIAMENTO DE PARCEIROS
      # ========================================
      def self.listar_parceiros(filtros = {})
        db = Database.db
        query = db[:gerencia_parceiros].order(Sequel.desc(:created_at))
        query = query.where(status: filtros[:status]) if filtros[:status] && !filtros[:status].empty?
        query.all
      end

      def self.criar_parceiro(params)
        db = Database.db
        db[:gerencia_parceiros].insert(
          nome: params[:nome],
          cidade: params[:cidade],
          uf: params[:uf],
          status: params[:status] || 'contatado',
          observacoes: params[:observacoes],
          created_at: Time.now
        )
      end

      def self.atualizar_parceiro(id, params)
        db = Database.db
        dados = {
          nome: params[:nome],
          cidade: params[:cidade],
          uf: params[:uf],
          status: params[:status],
          observacoes: params[:observacoes]
        }.compact
        db[:gerencia_parceiros].where(id: id.to_i).update(dados)
      end

      def self.excluir_parceiro(id)
        Database.db[:gerencia_parceiros].where(id: id.to_i).delete
      end

      def self.resumo_parceiros
        db = Database.db
        {
          contatados: db[:gerencia_parceiros].where(status: 'contatado').count,
          credenciados: db[:gerencia_parceiros].where(status: 'credenciado').count,
          aguardando: db[:gerencia_parceiros].where(status: 'aguardando').count,
          fracassados: db[:gerencia_parceiros].where(status: 'fracassado').count,
          total: db[:gerencia_parceiros].count
        }
      end

      # ========================================
      # COMERCIAL / MARKETING
      # ========================================
      def self.listar_comercial(filtros = {})
        db = Database.db
        query = db[:gerencia_comercial].order(Sequel.desc(:created_at))
        query = query.where(status: filtros[:status]) if filtros[:status] && !filtros[:status].empty?
        query.all
      end

      def self.criar_comercial(params)
        db = Database.db
        db[:gerencia_comercial].insert(
          razao_nome: params[:razao_nome],
          cnpj: params[:cnpj],
          cidade: params[:cidade],
          uf: params[:uf],
          solucao_oferecida: params[:solucao_oferecida],
          status: params[:status] || 'contatado',
          observacoes: params[:observacoes],
          created_at: Time.now
        )
      end

      def self.atualizar_comercial(id, params)
        db = Database.db
        dados = {
          razao_nome: params[:razao_nome],
          cnpj: params[:cnpj],
          cidade: params[:cidade],
          uf: params[:uf],
          solucao_oferecida: params[:solucao_oferecida],
          status: params[:status],
          observacoes: params[:observacoes]
        }.compact
        db[:gerencia_comercial].where(id: id.to_i).update(dados)
      end

      def self.excluir_comercial(id)
        Database.db[:gerencia_comercial].where(id: id.to_i).delete
      end

      def self.resumo_comercial
        db = Database.db
        {
          contatados: db[:gerencia_comercial].where(status: 'contatado').count,
          sucesso: db[:gerencia_comercial].where(status: 'sucesso').count,
          aguardando: db[:gerencia_comercial].where(status: 'aguardando').count,
          fracassados: db[:gerencia_comercial].where(status: 'fracassado').count,
          total: db[:gerencia_comercial].count
        }
      end

      # ========================================
      # REDES SOCIAIS
      # ========================================
      def self.listar_redes_sociais(filtros = {})
        db = Database.db
        query = db[:gerencia_redes_sociais].order(Sequel.desc(:created_at))
        query = query.where(plataforma: filtros[:plataforma]) if filtros[:plataforma] && !filtros[:plataforma].empty?
        query.all
      end

      def self.criar_rede_social(params)
        db = Database.db
        db[:gerencia_redes_sociais].insert(
          plataforma: params[:plataforma],
          tipo_conteudo: params[:tipo_conteudo],
          descricao: params[:descricao],
          data_publicacao: params[:data_publicacao],
          alcance: params[:alcance].to_i,
          engajamento: params[:engajamento].to_i,
          cliques: params[:cliques].to_i,
          conversoes: params[:conversoes].to_i,
          texto_engajamento: params[:texto_engajamento],
          status: params[:status] || 'planejado',
          created_at: Time.now
        )
      end

      def self.atualizar_rede_social(id, params)
        db = Database.db
        dados = {
          plataforma: params[:plataforma],
          tipo_conteudo: params[:tipo_conteudo],
          descricao: params[:descricao],
          data_publicacao: params[:data_publicacao],
          alcance: params[:alcance]&.to_i,
          engajamento: params[:engajamento]&.to_i,
          cliques: params[:cliques]&.to_i,
          conversoes: params[:conversoes]&.to_i,
          texto_engajamento: params[:texto_engajamento],
          status: params[:status]
        }.compact
        db[:gerencia_redes_sociais].where(id: id.to_i).update(dados)
      end

      def self.excluir_rede_social(id)
        Database.db[:gerencia_redes_sociais].where(id: id.to_i).delete
      end

      # ========================================
      # LICITAÇÕES
      # ========================================
      def self.listar_licitacoes(filtros = {})
        db = Database.db
        query = db[:gerencia_licitacoes].order(Sequel.desc(:created_at))
        query = query.where(status: filtros[:status]) if filtros[:status] && !filtros[:status].empty?
        query.all
      end

      def self.criar_licitacao(params)
        db = Database.db
        db[:gerencia_licitacoes].insert(
          nome_orgao: params[:nome_orgao],
          cidade: params[:cidade],
          uf: params[:uf],
          numero_edital: params[:numero_edital],
          objeto: params[:objeto],
          valor_estimado: parse_valor(params[:valor_estimado]),
          data_abertura: params[:data_abertura],
          status: params[:status] || 'inserida',
          portal: params[:portal],
          observacoes: params[:observacoes],
          created_at: Time.now
        )
      end

      def self.atualizar_licitacao(id, params)
        db = Database.db
        dados = {
          nome_orgao: params[:nome_orgao],
          cidade: params[:cidade],
          uf: params[:uf],
          numero_edital: params[:numero_edital],
          objeto: params[:objeto],
          valor_estimado: parse_valor(params[:valor_estimado]),
          data_abertura: params[:data_abertura],
          status: params[:status],
          portal: params[:portal],
          observacoes: params[:observacoes]
        }.compact
        db[:gerencia_licitacoes].where(id: id.to_i).update(dados)
      end

      def self.excluir_licitacao(id)
        Database.db[:gerencia_licitacoes].where(id: id.to_i).delete
      end

      def self.resumo_licitacoes
        db = Database.db
        {
          inseridas: db[:gerencia_licitacoes].where(status: 'inserida').count,
          cadastradas: db[:gerencia_licitacoes].where(status: 'cadastrada').count,
          andamento: db[:gerencia_licitacoes].where(status: 'andamento').count,
          ganhas: db[:gerencia_licitacoes].where(status: 'ganha').count,
          finalizadas: db[:gerencia_licitacoes].where(status: 'finalizada').count,
          total: db[:gerencia_licitacoes].count
        }
      end

      # ========================================
      # OPERAÇÕES E SUPORTE
      # ========================================
      def self.listar_treinamentos(filtros = {})
        db = Database.db
        query = db[:gerencia_treinamentos].order(Sequel.desc(:created_at))
        query.all
      end

      def self.criar_treinamento(params)
        db = Database.db
        db[:gerencia_treinamentos].insert(
          nome_cliente_fornecedor: params[:nome_cliente_fornecedor],
          solucao_treinada: params[:solucao_treinada],
          quem_treinou: params[:quem_treinou],
          data_treinamento: params[:data_treinamento],
          observacoes: params[:observacoes],
          created_at: Time.now
        )
      end

      def self.excluir_treinamento(id)
        Database.db[:gerencia_treinamentos].where(id: id.to_i).delete
      end

      def self.listar_chamados(filtros = {})
        db = Database.db
        query = db[:gerencia_chamados].order(Sequel.desc(:created_at))
        query = query.where(solucao: filtros[:solucao]) if filtros[:solucao] && !filtros[:solucao].empty?
        query = query.where(status: filtros[:status]) if filtros[:status] && !filtros[:status].empty?
        query.all
      end

      def self.criar_chamado(params)
        db = Database.db
        db[:gerencia_chamados].insert(
          solucao: params[:solucao],
          descricao: params[:descricao],
          aberto_por: params[:aberto_por],
          origem: params[:origem],
          status: params[:status] || 'aberto',
          prioridade: params[:prioridade] || 'media',
          created_at: Time.now
        )
      end

      def self.atualizar_chamado(id, params)
        db = Database.db
        dados = {
          solucao: params[:solucao],
          descricao: params[:descricao],
          aberto_por: params[:aberto_por],
          origem: params[:origem],
          status: params[:status],
          prioridade: params[:prioridade]
        }.compact
        db[:gerencia_chamados].where(id: id.to_i).update(dados)
      end

      def self.excluir_chamado(id)
        Database.db[:gerencia_chamados].where(id: id.to_i).delete
      end

      def self.listar_melhorias(filtros = {})
        db = Database.db
        query = db[:gerencia_melhorias].order(Sequel.desc(:created_at))
        query.all
      end

      def self.criar_melhoria(params)
        db = Database.db
        db[:gerencia_melhorias].insert(
          titulo: params[:titulo],
          descricao: params[:descricao],
          solucao: params[:solucao],
          status: params[:status] || 'planejada',
          data_implantacao: params[:data_implantacao],
          created_at: Time.now
        )
      end

      def self.atualizar_melhoria(id, params)
        db = Database.db
        dados = {
          titulo: params[:titulo],
          descricao: params[:descricao],
          solucao: params[:solucao],
          status: params[:status],
          data_implantacao: params[:data_implantacao]
        }.compact
        db[:gerencia_melhorias].where(id: id.to_i).update(dados)
      end

      def self.excluir_melhoria(id)
        Database.db[:gerencia_melhorias].where(id: id.to_i).delete
      end

      # ========================================
      # RESUMO GERAL GERÊNCIA
      # ========================================
      def self.resumo_geral
        db = Database.db
        {
          financeiro: {
            total_recebimentos: (db[:gerencia_recebimentos].sum(:valor) || 0).to_f,
            nf_clientes_abertas: db[:gerencia_nf_clientes].where(status: 'aberta').count,
            nf_fornecedores_abertas: db[:gerencia_nf_fornecedores].where(status: 'aberta').count,
            nf_pagas: db[:gerencia_nf_pagas].count
          },
          parceiros: resumo_parceiros,
          comercial: resumo_comercial,
          licitacoes: resumo_licitacoes,
          operacoes: {
            treinamentos: db[:gerencia_treinamentos].count,
            chamados_abertos: db[:gerencia_chamados].where(status: 'aberto').count,
            melhorias: db[:gerencia_melhorias].count
          }
        }
      end

      private

      def self.parse_valor(val)
        return 0 if val.nil? || val.to_s.strip.empty?
        val.to_s.gsub('.', '').gsub(',', '.').to_f
      end
    end
  end
end
