# frozen_string_literal: true
# services/relatorio.rb - Serviço de geração de relatórios e cálculos

module FinSystem
  module Services
    class Relatorio
      # Dados para gráfico de evolução mensal (últimos 6 meses)
      def self.evolucao_mensal(empresa_id = nil, meses = 6)
        db = FinSystem::Database.db
        resultado = []
        hoje = Date.today

        meses.times do |i|
          data = hoje << i
          mes = data.month
          ano = data.year
          inicio = Date.new(ano, mes, 1)
          fim = (inicio >> 1) - 1

          base = db[:movimentacoes].where(data_movimentacao: inicio..fim, status: 'confirmado')
          base = base.where(empresa_id: empresa_id.to_i) if empresa_id && !empresa_id.to_s.empty?

          receitas = base.where(tipo: 'receita').sum(:valor_bruto) || 0
          despesas = base.where(tipo: 'despesa').sum(:valor_bruto) || 0

          nomes = %w[_ Jan Fev Mar Abr Mai Jun Jul Ago Set Out Nov Dez]
          resultado.unshift({
            mes: "#{nomes[mes]}/#{ano}",
            mes_num: mes,
            ano: ano,
            receitas: receitas.to_f,
            despesas: despesas.to_f,
            resultado: (receitas - despesas).to_f
          })
        end

        resultado
      end

      # Dados para gráfico de pizza por categoria
      def self.por_categoria(empresa_id, mes, ano, tipo)
        db = FinSystem::Database.db
        inicio = Date.new(ano.to_i, mes.to_i, 1)
        fim = (inicio >> 1) - 1

        query = db[:movimentacoes]
                  .left_join(:categorias, Sequel[:categorias][:id] => Sequel[:movimentacoes][:categoria_id])
                  .where(Sequel[:movimentacoes][:data_movimentacao] => inicio..fim, Sequel[:movimentacoes][:status] => 'confirmado')
                  .where(Sequel[:movimentacoes][:tipo] => tipo)

        query = query.where(Sequel[:movimentacoes][:empresa_id] => empresa_id.to_i) if empresa_id && !empresa_id.to_s.empty?

        query.group(Sequel[:categorias][:nome], Sequel[:categorias][:cor])
             .select(
               Sequel[:categorias][:nome].as(:categoria),
               Sequel[:categorias][:cor].as(:cor),
               Sequel.function(:sum, Sequel[:movimentacoes][:valor_bruto]).as(:total)
             )
             .order(Sequel.desc(:total))
             .all
      end

      # Dados para gráfico pessoal
      def self.evolucao_pessoal(usuario_id, meses = 6)
        db = FinSystem::Database.db
        resultado = []
        hoje = Date.today

        meses.times do |i|
          data = hoje << i
          mes = data.month
          ano = data.year
          inicio = Date.new(ano, mes, 1)
          fim = (inicio >> 1) - 1

          base = db[:pessoal_movimentacoes].where(usuario_id: usuario_id, data_movimentacao: inicio..fim)

          receitas = base.where(tipo: 'receita').sum(:valor) || 0
          despesas = base.where(tipo: 'despesa').sum(:valor) || 0
          investimentos = base.where(tipo: 'investimento').sum(:valor) || 0

          resultado.unshift({
            mes: "#{mes}/#{ano}",
            receitas: receitas.to_f,
            despesas: despesas.to_f,
            investimentos: investimentos.to_f,
            saldo: (receitas - despesas - investimentos).to_f
          })
        end

        resultado
      end
    end
  end
end
