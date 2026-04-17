# frozen_string_literal: true
# controllers/cartoes_controller.rb - Gestão de cartões de crédito (empresarial)

module FinSystem
  module Controllers
    class CartoesController < Sinatra::Base
      helpers Middleware::Auth::AuthHelpers
      helpers Helpers::ViewHelpers

      set :views, File.join(File.dirname(__FILE__), '..', 'views')
      set :raise_errors, true

      before { autenticar_requisicao }

      # ========================================
      # CARTÕES EMPRESARIAIS
      # ========================================
      get '/cartoes' do
        requer_nivel('financeiro')
        @empresa_id = params[:empresa_id]
        @empresas = Models::Empresa.todas
        @cartoes = Models::CartaoCredito.resumo_cartoes(@empresa_id)
        @faturas_proximas = Models::CartaoCredito.faturas_proximas(@empresa_id)

        erb :'cartoes/index', layout: :'layouts/application'
      end

      # Criar cartão
      post '/cartoes' do
        requer_nivel('gerente')
        Models::CartaoCredito.criar(params)
        session[:flash_message] = 'Cartão de crédito cadastrado!'
        redirect '/cartoes'
      end

      # Atualizar cartão
      put '/cartoes/:id' do
        requer_nivel('gerente')
        Models::CartaoCredito.atualizar(params[:id].to_i, params)
        session[:flash_message] = 'Cartão atualizado!'
        redirect '/cartoes'
      end

      # Excluir cartão
      delete '/cartoes/:id' do
        requer_nivel('admin')
        Models::CartaoCredito.excluir(params[:id].to_i)
        session[:flash_message] = 'Cartão removido!'
        redirect '/cartoes'
      end

      # Detalhes da fatura
      get '/cartoes/:cartao_id/faturas/:id' do
        requer_nivel('financeiro')
        @cartao = Models::CartaoCredito.find(params[:cartao_id].to_i)
        halt 404 unless @cartao

        @fatura = Models::CartaoCredito.fatura_find(params[:id].to_i)
        halt 404 unless @fatura

        @despesas = Models::CartaoCredito.despesas_fatura(@fatura[:id]) || []
        @categorias = FinSystem::Database.db[:categorias].where(tipo: 'despesa', ativo: true).all || []

        erb :'cartoes/fatura', layout: :'layouts/application'
      end

      # Nova despesa no cartão
      post '/cartoes/:cartao_id/despesas' do
        requer_nivel('financeiro')
        cartao = Models::CartaoCredito.find(params[:cartao_id].to_i)
        halt 404 unless cartao

        params[:empresa_id] = cartao[:empresa_id]
        params[:usuario_id] = usuario_logado[:id]

        Models::CartaoCredito.criar_despesa_cartao(params)
        session[:flash_message] = 'Despesa lançada no cartão!'
        redirect "/cartoes"
      end

      # Editar despesa do cartão
      put '/cartoes/:cartao_id/despesas/:id' do
        requer_nivel('financeiro')
        despesa = Models::CartaoCredito.find_despesa(params[:id].to_i)
        halt 404 unless despesa

        Models::CartaoCredito.atualizar_despesa_cartao(params[:id].to_i, params)
        session[:flash_message] = 'Despesa atualizada com sucesso!'
        redirect "/cartoes/#{params[:cartao_id]}/faturas/#{despesa[:fatura_id]}"
      end

      # Excluir despesa do cartão
      delete '/cartoes/:cartao_id/despesas/:id' do
        requer_nivel('gerente')
        despesa = Models::CartaoCredito.find_despesa(params[:id].to_i)
        halt 404 unless despesa

        Models::CartaoCredito.excluir_despesa_cartao(params[:id].to_i)
        session[:flash_message] = 'Despesa removida!'
        redirect "/cartoes/#{params[:cartao_id]}/faturas/#{despesa[:fatura_id]}"
      end

      # ========================================
      # MARCAR FATURA COMO PAGA
      # ========================================
      post '/cartoes/:cartao_id/faturas/:id/pagar' do
        requer_nivel('financeiro')
        cartao = Models::CartaoCredito.find(params[:cartao_id].to_i)
        halt 404 unless cartao

        fatura = Models::CartaoCredito.fatura_find(params[:id].to_i)
        halt 404 unless fatura

        Models::CartaoCredito.pagar_fatura(fatura[:id], params[:data_pagamento])

        Models::AuditLog.registrar(
          usuario_id: usuario_logado[:id],
          acao: 'update',
          entidade: 'fatura_cartao',
          detalhes: "Fatura #{fatura[:mes_referencia]}/#{fatura[:ano_referencia]} do cartão #{cartao[:banco]} ••••#{cartao[:ultimos_digitos]} marcada como PAGA",
          ip: request.ip
        )

        session[:flash_message] = "Fatura #{fatura[:mes_referencia]}/#{fatura[:ano_referencia]} marcada como paga!"
        redirect "/cartoes/#{params[:cartao_id]}/faturas/#{fatura[:id]}"
      end

      # ========================================
      # CARTÕES PESSOAIS
      # ========================================
      get '/pessoal/cartoes' do
        @cartoes = Models::CartaoCredito.pessoal_resumo_cartoes(usuario_logado[:id]) || []
        @faturas_proximas = Models::CartaoCredito.pessoal_faturas_proximas(usuario_logado[:id]) || []
        @categorias = Models::Pessoal.categorias(usuario_logado[:id]) || []

        erb :'pessoal/cartoes', layout: :'layouts/application'
      end

      # Criar cartão pessoal
      post '/pessoal/cartoes' do
        params[:usuario_id] = usuario_logado[:id]
        Models::CartaoCredito.pessoal_criar(params)
        session[:flash_message] = 'Cartão pessoal cadastrado!'
        redirect '/pessoal/cartoes'
      end

      # Excluir cartão pessoal
      delete '/pessoal/cartoes/:id' do
        cartao = Models::CartaoCredito.pessoal_find(params[:id].to_i)
        halt 403 unless cartao && cartao[:usuario_id] == usuario_logado[:id]

        Models::CartaoCredito.pessoal_excluir(params[:id].to_i)
        session[:flash_message] = 'Cartão removido!'
        redirect '/pessoal/cartoes'
      end

      # Despesa no cartão pessoal
      post '/pessoal/cartoes/:cartao_id/despesas' do
        cartao = Models::CartaoCredito.pessoal_find(params[:cartao_id].to_i)
        halt 403 unless cartao && cartao[:usuario_id] == usuario_logado[:id]

        params[:usuario_id] = usuario_logado[:id]
        Models::CartaoCredito.pessoal_criar_despesa(params)
        session[:flash_message] = 'Despesa lançada no cartão!'
        redirect '/pessoal/cartoes'
      end

      # Editar despesa pessoal do cartão
      put '/pessoal/cartoes/:cartao_id/despesas/:id' do
        despesa = Models::CartaoCredito.pessoal_find_despesa(params[:id].to_i)
        halt 404 unless despesa
        cartao = Models::CartaoCredito.pessoal_find(params[:cartao_id].to_i)
        halt 403 unless cartao && cartao[:usuario_id] == usuario_logado[:id]

        Models::CartaoCredito.pessoal_atualizar_despesa(params[:id].to_i, params)
        session[:flash_message] = 'Despesa atualizada com sucesso!'
        redirect "/pessoal/cartoes/#{params[:cartao_id]}/faturas/#{despesa[:fatura_id]}"
      end

      # Excluir despesa pessoal do cartão
      delete '/pessoal/cartoes/:cartao_id/despesas/:id' do
        despesa = Models::CartaoCredito.pessoal_find_despesa(params[:id].to_i)
        halt 404 unless despesa
        cartao = Models::CartaoCredito.pessoal_find(params[:cartao_id].to_i)
        halt 403 unless cartao && cartao[:usuario_id] == usuario_logado[:id]

        Models::CartaoCredito.pessoal_excluir_despesa(params[:id].to_i)
        session[:flash_message] = 'Despesa removida!'
        redirect "/pessoal/cartoes/#{params[:cartao_id]}/faturas/#{despesa[:fatura_id]}"
      end

      # Fatura pessoal detalhes
      get '/pessoal/cartoes/:cartao_id/faturas/:id' do
        cartao = Models::CartaoCredito.pessoal_find(params[:cartao_id].to_i)
        halt 403 unless cartao && cartao[:usuario_id] == usuario_logado[:id]

        @cartao = cartao
        @fatura = FinSystem::Database.db[:pessoal_faturas].where(id: params[:id].to_i).first
        halt 404 unless @fatura

        @despesas = Models::CartaoCredito.pessoal_despesas_fatura(@fatura[:id]) || []
        @categorias = Models::Pessoal.categorias(usuario_logado[:id]) || []

        erb :'pessoal/fatura', layout: :'layouts/application'
      end
    end
  end
end
