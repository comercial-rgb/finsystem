# frozen_string_literal: true
# controllers/dashboard_controller.rb - Dashboard principal

module FinSystem
  module Controllers
    class DashboardController < Sinatra::Base
      helpers Middleware::Auth::AuthHelpers
      helpers Helpers::ViewHelpers

      set :views, File.join(File.dirname(__FILE__), '..', 'views')
      set :raise_errors, true

      before { autenticar_requisicao }

      # Dashboard principal
      get '/' do
        @mes = (params[:mes] || Date.today.month).to_i
        @ano = (params[:ano] || Date.today.year).to_i
        @empresa_id = params[:empresa_id]

        @empresas = Models::Empresa.todas

        # Resumo consolidado ou por empresa
        if @empresa_id && !@empresa_id.empty?
          @resumo = Models::Movimentacao.resumo_mensal(@empresa_id, @mes, @ano)
          @empresa_selecionada = Models::Empresa.find(@empresa_id.to_i)
        else
          # Consolidado de todas as empresas
          @resumo = { faturamento_bruto: 0, total_receitas: 0, total_despesas: 0,
                      total_antecipacoes: 0, lucro_antecipacoes: 0, qtd_movimentacoes: 0,
                      por_categoria: [], por_banco: [] }
          @empresas.each do |emp|
            r = Models::Movimentacao.resumo_mensal(emp[:id], @mes, @ano)
            @resumo[:faturamento_bruto] += r[:faturamento_bruto]
            @resumo[:total_receitas] += r[:total_receitas]
            @resumo[:total_despesas] += r[:total_despesas]
            @resumo[:total_antecipacoes] += r[:total_antecipacoes]
            @resumo[:lucro_antecipacoes] += r[:lucro_antecipacoes]
            @resumo[:qtd_movimentacoes] += r[:qtd_movimentacoes]
          end
        end

        @resultado = (@resumo[:total_receitas] || 0) + (@resumo[:lucro_antecipacoes] || 0) - (@resumo[:total_despesas] || 0)
        @saldos = Models::Movimentacao.saldo_por_conta(@empresa_id) || []

        # Últimas movimentações
        filtros = { mes: @mes, ano: @ano }
        filtros[:empresa_id] = @empresa_id if @empresa_id && !@empresa_id.empty?
        @ultimas_movimentacoes = Models::Movimentacao.listar(filtros).first(10) || []

        # Dados para gráficos
        @evolucao = _dados_evolucao(@empresa_id)
        @categorias_receita = _dados_categorias(@empresa_id, @mes, @ano, 'receita')
        @categorias_despesa = _dados_categorias(@empresa_id, @mes, @ano, 'despesa')

        # Lembretes de pagamento (despesas pendentes/recorrentes próximos 30 dias)
        @lembretes = _buscar_lembretes

        erb :'dashboard/index', layout: :'layouts/application'
      end

      private

      def _dados_evolucao(empresa_id)
        db = FinSystem::Database.db
        resultado = []
        hoje = Date.today
        6.times do |i|
          d = hoje << i
          inicio = Date.new(d.year, d.month, 1)
          fim = (inicio >> 1) - 1
          base = db[:movimentacoes].where(data_movimentacao: inicio..fim, status: %w[confirmado conciliado pendente]).exclude(tipo_operacao: 'transferencia')
          base = base.where(empresa_id: empresa_id.to_i) if empresa_id && !empresa_id.to_s.empty?
          rec = (base.where(tipo: 'receita').exclude(is_antecipacao: true).sum(:lucro) || 0).to_f
          desp = (base.where(tipo: 'despesa').exclude(is_antecipacao: true).sum(:valor_bruto) || 0).to_f
          resultado.unshift({ mes: "#{nome_mes(d.month)[0..2]}/#{d.year}", receitas: rec, despesas: desp, resultado: rec - desp })
        end
        resultado
      end

      def _dados_categorias(empresa_id, mes, ano, tipo)
        db = FinSystem::Database.db
        inicio = Date.new(ano.to_i, mes.to_i, 1)
        fim = (inicio >> 1) - 1
        query = db[:movimentacoes]
                  .left_join(:categorias, Sequel[:categorias][:id] => Sequel[:movimentacoes][:categoria_id])
                  .where(Sequel[:movimentacoes][:data_movimentacao] => inicio..fim, Sequel[:movimentacoes][:tipo] => tipo, Sequel[:movimentacoes][:status] => %w[confirmado conciliado pendente])
                  .exclude(Sequel[:movimentacoes][:tipo_operacao] => 'transferencia')
                  .exclude(Sequel[:movimentacoes][:is_antecipacao] => true)
        query = query.where(Sequel[:movimentacoes][:empresa_id] => empresa_id.to_i) if empresa_id && !empresa_id.to_s.empty?
        valor_col = tipo == 'receita' ? :lucro : :valor_bruto
        query.group(Sequel[:categorias][:nome], Sequel[:categorias][:cor])
             .select(Sequel[:categorias][:nome].as(:categoria), Sequel[:categorias][:cor].as(:cor), Sequel.function(:sum, Sequel[:movimentacoes][valor_col]).as(:total))
             .order(Sequel.desc(:total)).all
      end

      def _buscar_lembretes
        db = FinSystem::Database.db
        hoje = Date.today
        limite = hoje + 30

        # Despesas recorrentes e parceladas com vencimento próximo e não pagas
        begin
          return [] unless db[:movimentacoes].columns.include?(:tipo_cobranca)

          db[:movimentacoes]
            .left_join(:empresas, Sequel[:empresas][:id] => Sequel[:movimentacoes][:empresa_id])
            .where(Sequel[:movimentacoes][:tipo] => 'despesa')
            .where(Sequel[:movimentacoes][:pago] => false)
            .where(Sequel[:movimentacoes][:tipo_cobranca] => %w[recorrente parcelada])
            .where { Sequel[:movimentacoes][:data_proximo_vencimento] <= limite }
            .select_all(:movimentacoes)
            .select_append(Sequel[:empresas][:nome_fantasia].as(:empresa_nome))
            .order(Sequel[:movimentacoes][:data_proximo_vencimento])
            .limit(20)
            .all
        rescue
          []
        end
      end
    end
  end
end
