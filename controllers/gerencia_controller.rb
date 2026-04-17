# frozen_string_literal: true
# controllers/gerencia_controller.rb - Módulo completo de Gerência

module FinSystem
  module Controllers
    class GerenciaController < Sinatra::Base
      helpers Middleware::Auth::AuthHelpers
      helpers Helpers::ViewHelpers

      set :views, File.join(File.dirname(__FILE__), '..', 'views')
      set :method_override, true
      set :raise_errors, true

      before do
        autenticar_requisicao
        requer_nivel('gerente')
      end

      # ========================================
      # DASHBOARD GERÊNCIA
      # ========================================
      get '/gerencia' do
        @aba = params[:aba] || 'financeiro'
        @resumo = Models::Gerencia.resumo_geral

        # Financeiro
        @recebimentos = Models::Gerencia.listar_recebimentos(frente: params[:frente])
        @nf_clientes = Models::Gerencia.listar_nf_clientes(status: params[:nf_status])
        @nf_fornecedores = Models::Gerencia.listar_nf_fornecedores(status: params[:nf_forn_status])
        @nf_pagas = Models::Gerencia.listar_nf_pagas

        # Parceiros
        @parceiros = Models::Gerencia.listar_parceiros(status: params[:parc_status])
        @resumo_parceiros = Models::Gerencia.resumo_parceiros

        # Comercial
        @comercial = Models::Gerencia.listar_comercial(status: params[:com_status])
        @resumo_comercial = Models::Gerencia.resumo_comercial

        # Redes Sociais
        @redes_sociais = Models::Gerencia.listar_redes_sociais(plataforma: params[:plataforma])

        # Licitações
        @licitacoes = Models::Gerencia.listar_licitacoes(status: params[:lic_status])
        @resumo_licitacoes = Models::Gerencia.resumo_licitacoes

        # Operações
        @treinamentos = Models::Gerencia.listar_treinamentos
        @chamados = Models::Gerencia.listar_chamados(solucao: params[:ch_solucao], status: params[:ch_status])
        @melhorias = Models::Gerencia.listar_melhorias

        erb :'gerencia/index', layout: :'layouts/application'
      end

      # ========================================
      # RECEBIMENTOS
      # ========================================
      post '/gerencia/recebimentos' do
        Models::Gerencia.criar_recebimento(params)
        session[:flash_message] = 'Recebimento registrado com sucesso!'
        redirect "/gerencia?aba=financeiro"
      end

      delete '/gerencia/recebimentos/:id' do
        Models::Gerencia.excluir_recebimento(params[:id])
        session[:flash_message] = 'Recebimento excluído.'
        redirect "/gerencia?aba=financeiro"
      end

      # ========================================
      # NF CLIENTES
      # ========================================
      post '/gerencia/nf-clientes' do
        Models::Gerencia.criar_nf_cliente(params)
        session[:flash_message] = 'Nota fiscal de cliente registrada!'
        redirect "/gerencia?aba=financeiro"
      end

      put '/gerencia/nf-clientes/:id' do
        Models::Gerencia.atualizar_nf_cliente(params[:id], params)
        session[:flash_message] = 'Nota fiscal atualizada!'
        redirect "/gerencia?aba=financeiro"
      end

      delete '/gerencia/nf-clientes/:id' do
        Models::Gerencia.excluir_nf_cliente(params[:id])
        session[:flash_message] = 'Nota fiscal excluída.'
        redirect "/gerencia?aba=financeiro"
      end

      # Marcar NF cliente como paga (move para NF Pagas)
      post '/gerencia/nf-clientes/:id/pagar' do
        db = FinSystem::Database.db
        nf = db[:gerencia_nf_clientes].where(id: params[:id].to_i).first
        if nf
          Models::Gerencia.criar_nf_paga(
            nome_cliente: nf[:nome_cliente],
            centro_custo: nf[:centro_custo],
            periodo_apurado: nf[:periodo_apurado],
            data_vencimento: nf[:data_vencimento].to_s,
            valor_bruto: nf[:valor_bruto].to_s.gsub('.', ','),
            valor_liquido: nf[:valor_liquido].to_s.gsub('.', ',')
          )
          db[:gerencia_nf_clientes].where(id: params[:id].to_i).update(status: 'paga')
          session[:flash_message] = 'NF marcada como paga!'
        end
        redirect "/gerencia?aba=financeiro"
      end

      # ========================================
      # NF FORNECEDORES
      # ========================================
      post '/gerencia/nf-fornecedores' do
        Models::Gerencia.criar_nf_fornecedor(params)
        session[:flash_message] = 'Fatura de fornecedor registrada!'
        redirect "/gerencia?aba=financeiro"
      end

      put '/gerencia/nf-fornecedores/:id' do
        Models::Gerencia.atualizar_nf_fornecedor(params[:id], params)
        session[:flash_message] = 'Fatura atualizada!'
        redirect "/gerencia?aba=financeiro"
      end

      delete '/gerencia/nf-fornecedores/:id' do
        Models::Gerencia.excluir_nf_fornecedor(params[:id])
        session[:flash_message] = 'Fatura excluída.'
        redirect "/gerencia?aba=financeiro"
      end

      # ========================================
      # NF PAGAS
      # ========================================
      post '/gerencia/nf-pagas' do
        Models::Gerencia.criar_nf_paga(params)
        session[:flash_message] = 'NF paga registrada!'
        redirect "/gerencia?aba=financeiro"
      end

      delete '/gerencia/nf-pagas/:id' do
        Models::Gerencia.excluir_nf_paga(params[:id])
        session[:flash_message] = 'Registro excluído.'
        redirect "/gerencia?aba=financeiro"
      end

      # ========================================
      # PARCEIROS
      # ========================================
      post '/gerencia/parceiros' do
        Models::Gerencia.criar_parceiro(params)
        session[:flash_message] = 'Parceiro registrado!'
        redirect "/gerencia?aba=parceiros"
      end

      put '/gerencia/parceiros/:id' do
        Models::Gerencia.atualizar_parceiro(params[:id], params)
        session[:flash_message] = 'Parceiro atualizado!'
        redirect "/gerencia?aba=parceiros"
      end

      delete '/gerencia/parceiros/:id' do
        Models::Gerencia.excluir_parceiro(params[:id])
        session[:flash_message] = 'Parceiro excluído.'
        redirect "/gerencia?aba=parceiros"
      end

      # ========================================
      # COMERCIAL / MARKETING
      # ========================================
      post '/gerencia/comercial' do
        Models::Gerencia.criar_comercial(params)
        session[:flash_message] = 'Cliente comercial registrado!'
        redirect "/gerencia?aba=comercial"
      end

      put '/gerencia/comercial/:id' do
        Models::Gerencia.atualizar_comercial(params[:id], params)
        session[:flash_message] = 'Registro atualizado!'
        redirect "/gerencia?aba=comercial"
      end

      delete '/gerencia/comercial/:id' do
        Models::Gerencia.excluir_comercial(params[:id])
        session[:flash_message] = 'Registro excluído.'
        redirect "/gerencia?aba=comercial"
      end

      # ========================================
      # REDES SOCIAIS
      # ========================================
      post '/gerencia/redes-sociais' do
        Models::Gerencia.criar_rede_social(params)
        session[:flash_message] = 'Publicação registrada!'
        redirect "/gerencia?aba=redes"
      end

      put '/gerencia/redes-sociais/:id' do
        Models::Gerencia.atualizar_rede_social(params[:id], params)
        session[:flash_message] = 'Publicação atualizada!'
        redirect "/gerencia?aba=redes"
      end

      delete '/gerencia/redes-sociais/:id' do
        Models::Gerencia.excluir_rede_social(params[:id])
        session[:flash_message] = 'Publicação excluída.'
        redirect "/gerencia?aba=redes"
      end

      # ========================================
      # LICITAÇÕES
      # ========================================
      post '/gerencia/licitacoes' do
        Models::Gerencia.criar_licitacao(params)
        session[:flash_message] = 'Licitação registrada!'
        redirect "/gerencia?aba=licitacoes"
      end

      put '/gerencia/licitacoes/:id' do
        Models::Gerencia.atualizar_licitacao(params[:id], params)
        session[:flash_message] = 'Licitação atualizada!'
        redirect "/gerencia?aba=licitacoes"
      end

      delete '/gerencia/licitacoes/:id' do
        Models::Gerencia.excluir_licitacao(params[:id])
        session[:flash_message] = 'Licitação excluída.'
        redirect "/gerencia?aba=licitacoes"
      end

      # ========================================
      # OPERAÇÕES - TREINAMENTOS
      # ========================================
      post '/gerencia/treinamentos' do
        Models::Gerencia.criar_treinamento(params)
        session[:flash_message] = 'Treinamento registrado!'
        redirect "/gerencia?aba=operacoes"
      end

      delete '/gerencia/treinamentos/:id' do
        Models::Gerencia.excluir_treinamento(params[:id])
        session[:flash_message] = 'Treinamento excluído.'
        redirect "/gerencia?aba=operacoes"
      end

      # ========================================
      # OPERAÇÕES - CHAMADOS
      # ========================================
      post '/gerencia/chamados' do
        Models::Gerencia.criar_chamado(params)
        session[:flash_message] = 'Chamado registrado!'
        redirect "/gerencia?aba=operacoes"
      end

      put '/gerencia/chamados/:id' do
        Models::Gerencia.atualizar_chamado(params[:id], params)
        session[:flash_message] = 'Chamado atualizado!'
        redirect "/gerencia?aba=operacoes"
      end

      delete '/gerencia/chamados/:id' do
        Models::Gerencia.excluir_chamado(params[:id])
        session[:flash_message] = 'Chamado excluído.'
        redirect "/gerencia?aba=operacoes"
      end

      # ========================================
      # OPERAÇÕES - MELHORIAS
      # ========================================
      post '/gerencia/melhorias' do
        Models::Gerencia.criar_melhoria(params)
        session[:flash_message] = 'Melhoria registrada!'
        redirect "/gerencia?aba=operacoes"
      end

      put '/gerencia/melhorias/:id' do
        Models::Gerencia.atualizar_melhoria(params[:id], params)
        session[:flash_message] = 'Melhoria atualizada!'
        redirect "/gerencia?aba=operacoes"
      end

      delete '/gerencia/melhorias/:id' do
        Models::Gerencia.excluir_melhoria(params[:id])
        session[:flash_message] = 'Melhoria excluída.'
        redirect "/gerencia?aba=operacoes"
      end
    end
  end
end
