# frozen_string_literal: true
# config/app_config.rb - Configurações gerais da aplicação

module FinSystem
  module Config
    APP_NAME = 'FinSystem - Gestão Financeira'
    VERSION = '1.0.0'

    # Diretório de uploads de comprovantes
    UPLOAD_DIR = File.join(File.dirname(__FILE__), '..', 'data', 'uploads')
    UPLOAD_PESSOAL_DIR = File.join(UPLOAD_DIR, 'pessoal')
    MAX_UPLOAD_SIZE = 10 * 1024 * 1024  # 10MB

    # Tipos de arquivo permitidos para comprovantes
    ALLOWED_FILE_TYPES = %w[
      application/pdf
      image/jpeg
      image/png
      image/webp
    ].freeze

    # Sessão
    SESSION_EXPIRY_HOURS = 24
    SESSION_SECRET = begin
      require 'securerandom'
      require 'digest'
      raw = ENV.fetch('SESSION_SECRET') {
        if ENV['RACK_ENV'] == 'production'
          $stderr.puts '⚠️  SESSION_SECRET não definido! Gerando automaticamente.'
          SecureRandom.hex(64)
        else
          'finsystem_dev_secret_key_local_only_2024'
        end
      }
      # Sempre gerar 128 hex chars (64 bytes) para satisfazer Rack (>= 64 bytes)
      Digest::SHA256.hexdigest(raw) + Digest::SHA256.hexdigest(raw.reverse)
    end

    # Níveis de acesso
    ACCESS_LEVELS = {
      'admin'      => { label: 'Administrador', weight: 100 },
      'gerente'    => { label: 'Gerente', weight: 80 },
      'financeiro' => { label: 'Financeiro', weight: 60 },
      'operador'   => { label: 'Operador', weight: 40 },
      'pessoal'    => { label: 'Apenas Pessoal', weight: 10 }
    }.freeze

    # Bancos disponíveis
    BANCOS_BR = ['Itaú', 'Sicredi', 'Banco do Brasil', 'Bradesco', 'Santander', 'Caixa', 'Nubank', 'Inter', 'C6 Bank'].freeze
    BANCOS_US = ['Chase', 'Bank of America', 'Wells Fargo', 'PNC', 'TD Bank', 'Regions'].freeze

    # Moedas
    MOEDAS = { 'BRL' => 'R$', 'USD' => '$' }.freeze

    # Formas de pagamento
    FORMAS_PAGAMENTO = %w[pix ted boleto cartao_credito cartao_debito dinheiro cheque wire_transfer ach].freeze

    def self.ensure_directories
      [UPLOAD_DIR, UPLOAD_PESSOAL_DIR].each do |dir|
        FileUtils.mkdir_p(dir) unless Dir.exist?(dir)
      end
    end
  end
end
