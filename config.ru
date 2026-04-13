# frozen_string_literal: true
# config.ru - Configuração para rack/puma

require_relative 'app'

# Servir arquivos estáticos (CSS, JS, imagens) diretamente pelo Rack
# Isso garante que /images/, /css/, /js/ sejam servidos antes de qualquer controller
use Rack::Static, urls: ['/images', '/css', '/js', '/uploads', '/favicon.png'], root: 'public',
    header_rules: [
      [:all, { 'cache-control' => 'public, max-age=86400' }]
    ]

# ErrorCatcher como middleware externo captura erros de qualquer controller
use FinSystem::ErrorCatcher

run FinSystem::App
