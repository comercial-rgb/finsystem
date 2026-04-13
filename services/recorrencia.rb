# frozen_string_literal: true
# services/recorrencia.rb - Processamento de transações recorrentes

module FinSystem
  module Services
    class Recorrencia
      # Processar todas as transações recorrentes pendentes
      def self.processar_todas
        db = FinSystem::Database.db
        hoje = Date.today
        criadas = 0

        # Buscar todas as movimentações pessoais recorrentes
        recorrentes = db[:pessoal_movimentacoes].where(recorrente: true).all

        recorrentes.each do |mov|
          proxima_data = calcular_proxima_data(mov[:data_movimentacao], mov[:frequencia_recorrencia])

          # Gerar movimentações para todas as datas pendentes até hoje
          while proxima_data && proxima_data <= hoje
            # Verificar se já existe lançamento para esta data e descrição
            existente = db[:pessoal_movimentacoes].where(
              usuario_id: mov[:usuario_id],
              descricao: mov[:descricao],
              data_movimentacao: proxima_data,
              recorrente: false  # Lançamentos gerados automaticamente não são marcados como recorrentes
            ).first

            unless existente
              db[:pessoal_movimentacoes].insert(
                usuario_id: mov[:usuario_id],
                categoria_id: mov[:categoria_id],
                tipo: mov[:tipo],
                data_movimentacao: proxima_data,
                descricao: "#{mov[:descricao]} (recorrência)",
                valor: mov[:valor],
                forma_pagamento: mov[:forma_pagamento],
                observacoes: "Gerado automaticamente a partir de lançamento recorrente ##{mov[:id]}",
                recorrente: false,
                frequencia_recorrencia: nil
              )
              criadas += 1
            end

            proxima_data = calcular_proxima_data(proxima_data, mov[:frequencia_recorrencia])
          end
        end

        criadas
      end

      # Calcular próxima data com base na frequência
      def self.calcular_proxima_data(data_base, frequencia)
        return nil unless data_base && frequencia

        data_base = Date.parse(data_base.to_s) unless data_base.is_a?(Date)

        case frequencia
        when 'semanal'
          data_base + 7
        when 'quinzenal'
          data_base + 15
        when 'mensal'
          data_base >> 1
        when 'bimestral'
          data_base >> 2
        when 'trimestral'
          data_base >> 3
        when 'semestral'
          data_base >> 6
        when 'anual'
          data_base >> 12
        else
          data_base >> 1  # default: mensal
        end
      end

      # Listar transações recorrentes de um usuário
      def self.listar_recorrentes(usuario_id)
        FinSystem::Database.db[:pessoal_movimentacoes]
          .left_join(:pessoal_categorias, Sequel[:pessoal_categorias][:id] => Sequel[:pessoal_movimentacoes][:categoria_id])
          .where(Sequel[:pessoal_movimentacoes][:usuario_id] => usuario_id, Sequel[:pessoal_movimentacoes][:recorrente] => true)
          .select_all(:pessoal_movimentacoes)
          .select_append(Sequel[:pessoal_categorias][:nome].as(:categoria_nome))
          .select_append(Sequel[:pessoal_categorias][:cor].as(:categoria_cor))
          .order(:descricao)
          .all
      end
    end
  end
end
