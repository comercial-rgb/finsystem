# frozen_string_literal: true
# models/audit_log.rb - Registro de auditoria

module FinSystem
  module Models
    class AuditLog
      def self.db
        FinSystem::Database.db
      end

      def self.registrar(usuario_id:, acao:, entidade: nil, entidade_id: nil, detalhes: nil, ip: nil)
        db[:audit_logs].insert(
          usuario_id: usuario_id,
          acao: acao,
          entidade: entidade,
          entidade_id: entidade_id,
          detalhes: detalhes.is_a?(Hash) ? detalhes.to_json : detalhes,
          ip_address: ip
        )
      end

      def self.listar(filtros = {})
        query = db[:audit_logs]
                  .left_join(:usuarios, Sequel[:usuarios][:id] => Sequel[:audit_logs][:usuario_id])

        query = query.where(Sequel[:audit_logs][:usuario_id] => filtros[:usuario_id]) if filtros[:usuario_id]
        query = query.where(Sequel[:audit_logs][:entidade] => filtros[:entidade]) if filtros[:entidade]

        query
          .select_all(:audit_logs)
          .select_append(Sequel[:usuarios][:nome].as(:usuario_nome))
          .order(Sequel.desc(Sequel[:audit_logs][:created_at]))
          .limit(filtros[:limit] || 100)
          .all
      end
    end
  end
end
