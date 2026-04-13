# frozen_string_literal: true
# middleware/auth.rb - Middleware de autenticação e controle de sessão

require 'securerandom'

module FinSystem
  module Middleware
    module Auth
      def self.registered(app)
        app.helpers AuthHelpers
        app.before { autenticar_requisicao }
      end

      module AuthHelpers
        # Rotas públicas (não precisam de autenticação)
        ROTAS_PUBLICAS = %w[/login /auth/login /auth/logout /recuperar-senha /auth/recuperar-senha /auth/redefinir-senha].freeze

        def autenticar_requisicao
          return if ROTAS_PUBLICAS.any? { |r| request.path_info == r }
          return if request.path_info.start_with?('/public/')
          return if request.path_info.start_with?('/api/')
          return if request.path_info.start_with?('/redefinir-senha/')
          # Permitir acesso a arquivos estáticos (CSS, JS, imagens, uploads)
          return if request.path_info =~ /\.(css|js|png|jpg|jpeg|gif|svg|ico|woff2?|ttf|eot|map)$/i
          return if request.path_info.start_with?('/images/', '/css/', '/js/', '/uploads/')

          unless usuario_logado
            if request.xhr?
              halt 401, { error: 'Não autorizado' }.to_json
            else
              redirect '/login'
            end
          end
        end

        def usuario_logado
          return @usuario_logado if defined?(@usuario_logado)

          token = session[:auth_token]
          return nil unless token

          sessao = FinSystem::Database.db[:sessions]
                     .where(token: token)
                     .where { expires_at > Time.now }
                     .first
          return nil unless sessao

          @usuario_logado = Models::Usuario.find(sessao[:usuario_id])
        end

        def fazer_login(usuario, request)
          # Limpar sessões antigas do usuário
          FinSystem::Database.db[:sessions].where(usuario_id: usuario[:id]).delete

          # Criar nova sessão
          token = SecureRandom.hex(32)
          FinSystem::Database.db[:sessions].insert(
            usuario_id: usuario[:id],
            token: token,
            expires_at: Time.now + (Config::SESSION_EXPIRY_HOURS * 3600),
            ip_address: request.ip,
            user_agent: request.user_agent
          )

          session[:auth_token] = token

          Models::AuditLog.registrar(
            usuario_id: usuario[:id],
            acao: 'login',
            ip: request.ip
          )
        end

        def fazer_logout
          if usuario_logado
            Models::AuditLog.registrar(
              usuario_id: usuario_logado[:id],
              acao: 'logout',
              ip: request.ip
            )
          end

          token = session[:auth_token]
          FinSystem::Database.db[:sessions].where(token: token).delete if token
          session.clear
        end

        def requer_nivel(nivel)
          unless Models::Usuario.tem_permissao?(usuario_logado, nivel)
            if request.xhr?
              halt 403, { error: 'Sem permissão' }.to_json
            else
              session[:flash_error] = 'Você não tem permissão para acessar esta área.'
              redirect '/'
            end
          end
        end

        def flash_message
          msg = session.delete(:flash_message)
          msg
        end

        def flash_error
          msg = session.delete(:flash_error)
          msg
        end
      end
    end
  end
end
