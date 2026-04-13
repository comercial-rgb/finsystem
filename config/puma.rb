# frozen_string_literal: true
# config/puma.rb - Configuração do servidor Puma
# Otimizado para poucos acessos (gerente + sócios)

# Sem workers (single process) - evita problemas de fork + DB connection
# Suficiente para poucos usuários simultâneos
workers 0
threads_count = ENV.fetch('RAILS_MAX_THREADS', 5).to_i
threads threads_count, threads_count

port ENV.fetch('PORT', 4567)
environment ENV.fetch('RACK_ENV', 'development')

# NÃO usar stdout_redirect no Render - ele captura stdout/stderr nativamente
# NÃO usar preload_app! com workers=0 (desnecessário)
