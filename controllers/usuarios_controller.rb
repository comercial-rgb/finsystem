# frozen_string_literal: true
# controllers/usuarios_controller.rb - Gestão de usuários

module FinSystem
  module Controllers
    class UsuariosController < Sinatra::Base
      helpers Middleware::Auth::AuthHelpers
      helpers Helpers::ViewHelpers

      set :views, File.join(File.dirname(__FILE__), '..', 'views')
      set :raise_errors, true

      before { autenticar_requisicao }

      # Listar usuários
      get '/usuarios' do
        requer_nivel('admin')
        @usuarios = Models::Usuario.todos
        erb :'usuarios/index', layout: :'layouts/application'
      end

      # Novo usuário
      get '/usuarios/novo' do
        requer_nivel('admin')
        erb :'usuarios/form', layout: :'layouts/application'
      end

      # Criar usuário
      post '/usuarios' do
        requer_nivel('admin')
        begin
          Models::Usuario.criar(params)

          Models::AuditLog.registrar(
            usuario_id: usuario_logado[:id],
            acao: 'create',
            entidade: 'usuario',
            detalhes: "Usuário criado: #{params[:nome]} (#{params[:email]})",
            ip: request.ip
          )

          session[:flash_message] = "Usuário #{params[:nome]} criado!"
          redirect '/usuarios'
        rescue Sequel::UniqueConstraintViolation
          session[:flash_error] = 'Email já cadastrado!'
          redirect '/usuarios/novo'
        end
      end

      # Editar usuário
      get '/usuarios/:id/editar' do
        requer_nivel('admin')
        @usuario = Models::Usuario.find(params[:id].to_i)
        halt 404 unless @usuario
        erb :'usuarios/edit', layout: :'layouts/application'
      end

      # Atualizar usuário
      put '/usuarios/:id' do
        requer_nivel('admin')
        Models::Usuario.atualizar(params[:id].to_i, params)
        session[:flash_message] = 'Usuário atualizado!'
        redirect '/usuarios'
      end

      # Desativar usuário
      delete '/usuarios/:id' do
        requer_nivel('admin')
        Models::Usuario.desativar(params[:id].to_i)
        session[:flash_message] = 'Usuário desativado!'
        redirect '/usuarios'
      end

      # ========================================
      # AUDIT LOG
      # ========================================
      get '/auditoria' do
        requer_nivel('admin')
        @logs = Models::AuditLog.listar(limit: 200)
        erb :'usuarios/auditoria', layout: :'layouts/application'
      end
    end
  end
end
