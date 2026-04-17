# frozen_string_literal: true
# models/usuario.rb - Model de usuário com autenticação

require 'bcrypt'

module FinSystem
  module Models
    class Usuario
      def self.db
        FinSystem::Database.db
      end

      def self.table
        db[:usuarios]
      end

      # Criar novo usuário
      def self.criar(params)
        table.insert(
          nome: params[:nome],
          email: params[:email].downcase.strip,
          senha_hash: BCrypt::Password.create(params[:senha]),
          nivel_acesso: params[:nivel_acesso] || 'operador',
          ativo: true
        )
      end

      # Autenticar usuário
      def self.autenticar(email, senha)
        user = table.where(email: email.downcase.strip, ativo: true).first
        return nil unless user
        return nil unless BCrypt::Password.new(user[:senha_hash]) == senha

        # Atualizar último login
        table.where(id: user[:id]).update(ultimo_login: Time.now)
        user
      end

      # Buscar por ID
      def self.find(id)
        table.where(id: id).first
      end

      # Listar todos ativos
      def self.todos
        table.where(ativo: true).order(:nome).all
      end

      # Atualizar dados
      def self.atualizar(id, params)
        update_data = {}
        update_data[:nome] = params[:nome] if params[:nome]
        update_data[:email] = params[:email].downcase.strip if params[:email]
        update_data[:nivel_acesso] = params[:nivel_acesso] if params[:nivel_acesso]
        update_data[:senha_hash] = BCrypt::Password.create(params[:senha]) if params[:senha] && !params[:senha].empty?
        update_data[:updated_at] = Time.now
        table.where(id: id).update(update_data)
      end

      # Desativar (soft delete)
      def self.desativar(id)
        table.where(id: id).update(ativo: false, updated_at: Time.now)
      end

      # Verificar se tem permissão
      def self.tem_permissao?(user, nivel_requerido)
        return false unless user
        niveis = Config::ACCESS_LEVELS
        return false unless niveis[user[:nivel_acesso]] && niveis[nivel_requerido]

        niveis[user[:nivel_acesso]][:weight] >= niveis[nivel_requerido][:weight]
      end
    end
  end
end
