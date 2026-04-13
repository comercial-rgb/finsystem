# frozen_string_literal: true
# app.rb - Arquivo principal do FinSystem
# Uso: ruby app.rb (ou bundle exec ruby app.rb)

require 'sinatra/base'
require 'sinatra/contrib'
require 'json'
require 'securerandom'
require 'fileutils'
require 'bigdecimal'
require 'date'

# ========================================
# CARREGAR MÓDULOS
# ========================================
require_relative 'config/app_config'
require_relative 'db/database'
require_relative 'db/migrations'
require_relative 'db/seeds'

require_relative 'helpers/view_helpers'
require_relative 'middleware/auth'

require_relative 'models/usuario'
require_relative 'models/empresa'
require_relative 'models/movimentacao'
require_relative 'models/comprovante'
require_relative 'models/pessoal'
require_relative 'models/audit_log'
require_relative 'models/cartao_credito'

require_relative 'services/validation'
require_relative 'services/recorrencia'
require_relative 'services/relatorio'

require_relative 'controllers/auth_controller'
require_relative 'controllers/dashboard_controller'
require_relative 'controllers/movimentacoes_controller'
require_relative 'controllers/empresas_controller'
require_relative 'controllers/pessoal_controller'
require_relative 'controllers/usuarios_controller'
require_relative 'controllers/relatorios_controller'
require_relative 'controllers/clientes_controller'
require_relative 'controllers/fornecedores_controller'
require_relative 'controllers/cartoes_controller'
require_relative 'controllers/api_controller'

module FinSystem
  # ========================================
  # MIDDLEWARE DE CAPTURA DE ERROS GLOBAL
  # Captura erros de TODOS os controllers
  # ========================================
  class ErrorCatcher
    def initialize(app)
      @app = app
    end

    def call(env)
      @app.call(env)
    rescue => e
      $stderr.puts "[FINSYSTEM ERROR] #{e.class}: #{e.message}"
      $stderr.puts e.backtrace&.first(15)&.join("\n")
      body = if ENV['RACK_ENV'] == 'production'
        "<html><body style='font-family:sans-serif;text-align:center;padding:60px'>"\
        "<h1 style='color:#ef4444'>Erro Interno</h1>"\
        "<p style='color:#64748b'>#{e.class}: #{e.message}</p>"\
        "<p><a href='/' style='color:#6366f1'>Voltar ao Dashboard</a></p></body></html>"
      else
        "<pre>#{e.class}: #{e.message}\n#{e.backtrace&.first(20)&.join("\n")}</pre>"
      end
      [500, { 'content-type' => 'text/html' }, [body]]
    end
  end

  class App < Sinatra::Base
    # ========================================
    # CONFIGURAÇÃO
    # ========================================
    configure do
      set :root, File.dirname(__FILE__)
      set :views, File.join(File.dirname(__FILE__), 'views')
      set :public_folder, File.join(File.dirname(__FILE__), 'public')
      set :bind, '0.0.0.0'
      set :port, 4567
      set :server, :puma
      set :show_exceptions, :after_handler
      set :method_override, true

      # Sessão: usar Rack::Session::Cookie explicitamente (HMAC-signed)
      # Evita Rack::Protection::EncryptedCookie que exige key de exatamente 32 bytes AES
      disable :sessions
      set :session_store, Rack::Session::Cookie

      # Garantir diretórios
      Config.ensure_directories
    end

    # Sessão configurada manualmente como middleware (antes dos controllers)
    use Rack::Session::Cookie,
      key: 'rack.session',
      secret: Config::SESSION_SECRET,
      expire_after: Config::SESSION_EXPIRY_HOURS * 3600

    # Capturar erros de todos os controllers (middleware global)
    use ErrorCatcher

    # Permitir PUT/DELETE via _method em formulários (precisa estar antes dos controllers)
    use Rack::MethodOverride

    configure :development do
      set :show_exceptions, true
      set :logging, true
    end

    configure :production do
      set :show_exceptions, false
      set :dump_errors, true
      set :logging, true
    end

    # ========================================
    # INICIALIZAR BANCO
    # ========================================
    db = Database.connect(settings.environment || :development)
    Migrations.run(db)

    # Rodar seeds apenas se não houver usuários
    if db[:usuarios].count == 0
      Seeds.run(db)
    end

    # Processar transações recorrentes pendentes
    begin
      criadas = Services::Recorrencia.processar_todas
      puts "  🔄 #{criadas} transação(ões) recorrente(s) gerada(s)" if criadas > 0
    rescue => e
      puts "  ⚠️  Erro ao processar recorrências: #{e.message}"
    end

    # ========================================
    # MONTAR CONTROLLERS
    # ========================================
    use Controllers::AuthController
    use Controllers::DashboardController
    use Controllers::MovimentacoesController
    use Controllers::EmpresasController
    use Controllers::PessoalController
    use Controllers::UsuariosController
    use Controllers::RelatoriosController
    use Controllers::ClientesController
    use Controllers::FornecedoresController
    use Controllers::CartoesController
    use Controllers::ApiController

    # ========================================
    # ROTA FALLBACK (404)
    # ========================================
    not_found do
      erb :not_found, layout: false rescue
      "<h1 style='text-align:center;margin-top:100px;font-family:sans-serif;color:#64748b'>404 - Página não encontrada</h1>
       <p style='text-align:center;font-family:sans-serif'><a href='/' style='color:#6366f1'>Voltar ao Dashboard</a></p>"
    end

    # ========================================
    # ERROS
    # ========================================
    error do
      err = env['sinatra.error']
      msg = err ? "#{err.class}: #{err.message}" : 'Erro desconhecido'
      bt = err&.backtrace&.first(10)&.join("\n") || ''
      $stderr.puts "[FINSYSTEM ERROR] #{msg}\n#{bt}"
      "<h1 style='text-align:center;margin-top:100px;font-family:sans-serif;color:#ef4444'>Erro Interno</h1>
       <p style='text-align:center;font-family:sans-serif;color:#64748b'>#{msg}</p>
       <p style='text-align:center'><a href='/' style='color:#6366f1'>Voltar ao Dashboard</a></p>"
    end
  end
end

# ========================================
# INICIAR SERVIDOR
# ========================================
if __FILE__ == $PROGRAM_NAME
  puts ""
  puts "╔══════════════════════════════════════════════════╗"
  puts "║           FinSystem v#{FinSystem::Config::VERSION}                            ║"
  puts "║     Gestão Financeira Multi-Empresa                  ║"
  puts "║                                                      ║"
  puts "║  🌐 http://localhost:4567                            ║"
  puts "║                                                      ║"
  puts "║  👤 Admin Geral:                                     ║"
  puts "║     📧 admin@frotainstasolutions.com.br              ║"
  puts "║     🔑 FrotaInsta@2026!                              ║"
  puts "║                                                      ║"
  puts "║  👤 Admin Winner:                                    ║"
  puts "║     📧 admin@instasolutions.com.br                   ║"
  puts "║     🔑 admin123                                      ║"
  puts "║                                                      ║"
  puts "║  ⚠️  Troque as senhas padrão em produção!            ║"
  puts "╚══════════════════════════════════════════════════════╝"
  puts ""

  FinSystem::App.run!
end
