# frozen_string_literal: true
# config.ru - Configuração para rack/puma

require_relative 'app'

# ErrorCatcher como middleware externo captura erros de qualquer controller
use FinSystem::ErrorCatcher

run FinSystem::App
