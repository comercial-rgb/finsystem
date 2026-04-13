# frozen_string_literal: true
# controllers/clientes_controller.rb - CRUD completo de clientes

module FinSystem
  module Controllers
    class ClientesController < Sinatra::Base
      helpers Middleware::Auth::AuthHelpers
      helpers Helpers::ViewHelpers

      set :views, File.join(File.dirname(__FILE__), '..', 'views')
      set :raise_errors, true

      before { autenticar_requisicao }

      # Listar clientes
      get '/clientes' do
        requer_nivel('operador')
        @empresa_id = params[:empresa_id]
        @busca = params[:busca]
        @page = (params[:page] || 1).to_i
        @per_page = 20

        @empresas = Models::Empresa.todas

        query = FinSystem::Database.db[:clientes]
                  .left_join(:empresas, Sequel[:empresas][:id] => Sequel[:clientes][:empresa_id])
                  .select_all(:clientes)
                  .select_append(Sequel[:empresas][:nome_fantasia].as(:empresa_nome))

        query = query.where(Sequel[:clientes][:empresa_id] => @empresa_id.to_i) if @empresa_id && !@empresa_id.empty?
        query = query.where(Sequel.like(Sequel[:clientes][:nome], "%#{@busca}%") | Sequel.like(Sequel[:clientes][:cnpj_cpf_ein], "%#{@busca}%")) if @busca && !@busca.empty?

        @total = query.count
        @total_pages = (@total / @per_page.to_f).ceil
        @clientes = query.order(Sequel[:clientes][:nome]).limit(@per_page).offset((@page - 1) * @per_page).all

        erb :'clientes/index', layout: :'layouts/application'
      end

      # Novo cliente
      get '/clientes/novo' do
        requer_nivel('operador')
        @empresas = Models::Empresa.todas
        @cliente = {}
        erb :'clientes/form', layout: :'layouts/application'
      end

      # Criar cliente
      post '/clientes' do
        requer_nivel('operador')

        errors = Services::Validation.validate_cliente(params)
        unless errors.empty?
          session[:flash_error] = errors.join(', ')
          redirect '/clientes/novo'
          return
        end

        FinSystem::Database.db[:clientes].insert(
          empresa_id: params[:empresa_id]&.to_i,
          nome: params[:nome].strip,
          cnpj_cpf_ein: params[:cnpj_cpf_ein]&.strip,
          tipo: params[:tipo] || 'PJ',
          email: params[:email]&.strip,
          telefone: params[:telefone]&.strip,
          cidade: params[:cidade]&.strip,
          estado: params[:estado]&.strip,
          pais: params[:pais] || 'BR'
        )

        Models::AuditLog.registrar(
          usuario_id: usuario_logado[:id],
          acao: 'create',
          entidade: 'cliente',
          detalhes: "Cliente criado: #{params[:nome]}",
          ip: request.ip
        )

        session[:flash_message] = "Cliente #{params[:nome]} cadastrado!"
        redirect '/clientes'
      end

      # Editar cliente
      get '/clientes/:id/editar' do
        requer_nivel('operador')
        @cliente = FinSystem::Database.db[:clientes].where(id: params[:id].to_i).first
        halt 404 unless @cliente
        @empresas = Models::Empresa.todas
        erb :'clientes/form', layout: :'layouts/application'
      end

      # Atualizar cliente
      put '/clientes/:id' do
        requer_nivel('operador')

        errors = Services::Validation.validate_cliente(params)
        unless errors.empty?
          session[:flash_error] = errors.join(', ')
          redirect "/clientes/#{params[:id]}/editar"
          return
        end

        FinSystem::Database.db[:clientes].where(id: params[:id].to_i).update(
          empresa_id: params[:empresa_id]&.to_i,
          nome: params[:nome].strip,
          cnpj_cpf_ein: params[:cnpj_cpf_ein]&.strip,
          tipo: params[:tipo] || 'PJ',
          email: params[:email]&.strip,
          telefone: params[:telefone]&.strip,
          cidade: params[:cidade]&.strip,
          estado: params[:estado]&.strip,
          pais: params[:pais] || 'BR'
        )

        Models::AuditLog.registrar(
          usuario_id: usuario_logado[:id],
          acao: 'update',
          entidade: 'cliente',
          entidade_id: params[:id].to_i,
          detalhes: "Cliente atualizado: #{params[:nome]}",
          ip: request.ip
        )

        session[:flash_message] = 'Cliente atualizado!'
        redirect '/clientes'
      end

      # Desativar cliente
      delete '/clientes/:id' do
        requer_nivel('gerente')
        FinSystem::Database.db[:clientes].where(id: params[:id].to_i).update(ativo: false)

        Models::AuditLog.registrar(
          usuario_id: usuario_logado[:id],
          acao: 'delete',
          entidade: 'cliente',
          entidade_id: params[:id].to_i,
          ip: request.ip
        )

        session[:flash_message] = 'Cliente desativado!'
        redirect '/clientes'
      end
    end
  end
end
