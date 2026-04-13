# frozen_string_literal: true
# db/database.rb - Configuração e conexão com banco de dados
# Suporta SQLite (development) e PostgreSQL (production via DATABASE_URL)

require 'sequel'
require 'logger'

module FinSystem
  module Database
    def self.connect(env = :development)
      return @db if @db

      if ENV['DATABASE_URL'] && !ENV['DATABASE_URL'].empty?
        # Produção: PostgreSQL via DATABASE_URL (Render, Railway, etc.)
        @db = Sequel.connect(ENV['DATABASE_URL'], max_connections: 10)
        puts "  📦 Banco: PostgreSQL (produção)"
      else
        # Desenvolvimento: SQLite local
        db_path = File.join(File.dirname(__FILE__), '..', 'data')
        Dir.mkdir(db_path) unless Dir.exist?(db_path)

        db_file = case env
                  when :test then File.join(db_path, 'finsystem_test.db')
                  else File.join(db_path, 'finsystem.db')
                  end

        @db = Sequel.sqlite(db_file)
        puts "  📦 Banco: SQLite (#{db_file})"
      end

      @db.loggers << Logger.new($stdout) if env == :development
      @db.extension :date_arithmetic
      @db
    end

    def self.db
      @db || connect
    end
  end
end
