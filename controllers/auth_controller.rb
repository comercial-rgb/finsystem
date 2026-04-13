# frozen_string_literal: true
# controllers/auth_controller.rb - Rotas de autenticação

module FinSystem
  module Controllers
    class AuthController < Sinatra::Base
      helpers Middleware::Auth::AuthHelpers
      helpers Helpers::ViewHelpers

      set :views, File.join(File.dirname(__FILE__), '..', 'views')
      set :raise_errors, true

      # Página de login
      get '/login' do
        erb :'layouts/login', layout: false
      end

      # Processar login
      post '/auth/login' do
        usuario = Models::Usuario.autenticar(params[:email], params[:senha])

        if usuario
          fazer_login(usuario, request)
          redirect '/'
        else
          @erro = 'Email ou senha inválidos'
          erb :'layouts/login', layout: false
        end
      end

      # Logout
      get '/auth/logout' do
        fazer_logout
        redirect '/login'
      end

      # ========================================
      # RECUPERAÇÃO DE SENHA
      # ========================================
      get '/recuperar-senha' do
        erb :'layouts/recuperar_senha', layout: false
      end

      post '/auth/recuperar-senha' do
        email = params[:email]&.downcase&.strip
        user = FinSystem::Database.db[:usuarios].where(email: email, ativo: true).first

        if user
          # Gerar token
          token = SecureRandom.hex(32)
          FinSystem::Database.db[:password_reset_tokens].insert(
            usuario_id: user[:id],
            token: token,
            expires_at: Time.now + 3600  # 1 hora
          )

          # Em produção, enviar email. Aqui, mostramos o link.
          @reset_link = "/redefinir-senha/#{token}"
          @user_nome = user[:nome]
          erb :'layouts/recuperar_senha_enviado', layout: false
        else
          @erro = 'Nenhuma conta encontrada com este email'
          erb :'layouts/recuperar_senha', layout: false
        end
      end

      # Formulário de nova senha
      get '/redefinir-senha/:token' do
        @token = params[:token]
        reset = FinSystem::Database.db[:password_reset_tokens]
                  .where(token: @token, used: false)
                  .where { expires_at > Time.now }
                  .first

        if reset
          erb :'layouts/redefinir_senha', layout: false
        else
          @erro = 'Link inválido ou expirado'
          erb :'layouts/recuperar_senha', layout: false
        end
      end

      # Processar nova senha
      post '/auth/redefinir-senha' do
        token = params[:token]
        reset = FinSystem::Database.db[:password_reset_tokens]
                  .where(token: token, used: false)
                  .where { expires_at > Time.now }
                  .first

        if reset && params[:senha] && params[:senha].length >= 6
          if params[:senha_confirmacao] && params[:senha] != params[:senha_confirmacao]
            @erro = 'As senhas não coincidem'
            @token = token
            return erb(:'layouts/redefinir_senha', layout: false)
          end

          # Atualizar senha
          Models::Usuario.atualizar(reset[:usuario_id], { senha: params[:senha] })

          # Marcar token como usado
          FinSystem::Database.db[:password_reset_tokens].where(id: reset[:id]).update(used: true)

          Models::AuditLog.registrar(
            usuario_id: reset[:usuario_id],
            acao: 'password_reset',
            detalhes: 'Senha redefinida via token',
            ip: request.ip
          )

          @sucesso = true
          erb :'layouts/redefinir_senha', layout: false
        else
          @erro = 'Token inválido ou senha muito curta (mínimo 6 caracteres)'
          @token = token
          erb :'layouts/redefinir_senha', layout: false
        end
      end
    end
  end
end
