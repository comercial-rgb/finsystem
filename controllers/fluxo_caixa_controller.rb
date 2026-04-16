# frozen_string_literal: true
# controllers/fluxo_caixa_controller.rb - Fluxo de Caixa detalhado

module FinSystem
  module Controllers
    class FluxoCaixaController < Sinatra::Base
      helpers Middleware::Auth::AuthHelpers
      helpers Helpers::ViewHelpers

      set :views, File.join(File.dirname(__FILE__), '..', 'views')
      set :raise_errors, true

      before { autenticar_requisicao }

      get '/fluxo-de-caixa' do
        @mes = (params[:mes] || Date.today.month).to_i
        @ano = (params[:ano] || Date.today.year).to_i
        @empresa_id = params[:empresa_id]

        @empresas = Models::Empresa.todas
        db = FinSystem::Database.db

        inicio = Date.new(@ano, @mes, 1)
        fim = (inicio >> 1) - 1

        # Base query for the month
        base = db[:movimentacoes].where(
          data_movimentacao: inicio..fim,
          status: %w[confirmado conciliado pendente]
        ).exclude(tipo_operacao: 'transferencia')
        base = base.where(empresa_id: @empresa_id.to_i) if @empresa_id && !@empresa_id.to_s.empty?

        # ========================================
        # ENTRADAS (Receitas)
        # ========================================
        receitas = base.where(tipo: 'receita').exclude(is_antecipacao: true)
        @faturamento_bruto = (receitas.sum(:valor_bruto) || 0).to_f
        @receita_real = (receitas.sum(:lucro) || 0).to_f
        @repasse_fornecedores = @faturamento_bruto - @receita_real

        # ========================================
        # ANTECIPAÇÕES
        # ========================================
        antecipacoes_desp = base.where(tipo: 'despesa', is_antecipacao: true)
        antecipacoes_rec = base.where(tipo: 'receita', is_antecipacao: true)
        @total_antecipado = (antecipacoes_desp.sum(:valor_bruto) || 0).to_f
        @lucro_antecipacoes = (antecipacoes_rec.sum(:valor_bruto) || 0).to_f
        @qtd_antecipacoes = antecipacoes_desp.count

        # ========================================
        # DESPESAS (excluindo antecipações)
        # ========================================
        despesas = base.where(tipo: 'despesa').exclude(is_antecipacao: true)
        @total_despesas = (despesas.sum(:valor_bruto) || 0).to_f

        # Por tipo de cobrança
        @despesas_recorrentes = (despesas.where(tipo_cobranca: 'recorrente').sum(:valor_bruto) || 0).to_f
        @despesas_parceladas = (despesas.where(tipo_cobranca: 'parcelada').sum(:valor_bruto) || 0).to_f
        @despesas_unicas = (despesas.where(tipo_cobranca: 'unica').sum(:valor_bruto) || 0).to_f
        @despesas_sem_tipo = @total_despesas - @despesas_recorrentes - @despesas_parceladas - @despesas_unicas

        # Top despesas por categoria
        @despesas_por_categoria = despesas
          .left_join(:categorias, Sequel[:categorias][:id] => Sequel[:movimentacoes][:categoria_id])
          .group(Sequel[:categorias][:nome], Sequel[:categorias][:cor])
          .select(
            Sequel[:categorias][:nome].as(:categoria),
            Sequel[:categorias][:cor].as(:cor),
            Sequel.function(:sum, Sequel[:movimentacoes][:valor_bruto]).as(:total),
            Sequel.function(:count, Sequel[:movimentacoes][:id]).as(:qtd)
          )
          .order(Sequel.desc(:total)).all

        # ========================================
        # CARTÕES DE CRÉDITO (faturas do mês)
        # ========================================
        @despesas_cartao = begin
          if db.table_exists?(:cartoes_credito)
            db[:cartoes_credito]
              .left_join(:fatura_items, Sequel[:fatura_items][:cartao_id] => Sequel[:cartoes_credito][:id])
              .where(Sequel[:fatura_items][:mes_referencia] => @mes, Sequel[:fatura_items][:ano_referencia] => @ano)
              .sum(Sequel[:fatura_items][:valor]) || 0
          else
            0
          end
        rescue
          0
        end

        # ========================================
        # RESULTADO LÍQUIDO
        # ========================================
        @resultado_liquido = @receita_real + @lucro_antecipacoes - @total_despesas

        # ========================================
        # SALDOS BANCÁRIOS
        # ========================================
        @saldos = Models::Movimentacao.saldo_por_conta(@empresa_id)
        @saldo_total = @saldos.sum { |s| (s[:saldo_inicial] || 0) + (s[:total_entradas] || 0) - (s[:total_saidas] || 0) }

        # ========================================
        # DESPESAS RECORRENTES PENDENTES (próximos 30 dias)
        # ========================================
        @pendentes_recorrentes = begin
          query = db[:movimentacoes]
            .left_join(:empresas, Sequel[:empresas][:id] => Sequel[:movimentacoes][:empresa_id])
            .left_join(:categorias, Sequel[:categorias][:id] => Sequel[:movimentacoes][:categoria_id])
            .where(Sequel[:movimentacoes][:tipo] => 'despesa', Sequel[:movimentacoes][:pago] => false)
            .where(Sequel[:movimentacoes][:tipo_cobranca] => %w[recorrente parcelada])
            .where { Sequel[:movimentacoes][:data_proximo_vencimento] <= (Date.today + 60) }
            .select_all(:movimentacoes)
            .select_append(Sequel[:empresas][:nome_fantasia].as(:empresa_nome))
            .select_append(Sequel[:categorias][:nome].as(:categoria_nome))
            .order(Sequel[:movimentacoes][:data_proximo_vencimento])
            .limit(30)
          query = query.where(Sequel[:movimentacoes][:empresa_id] => @empresa_id.to_i) if @empresa_id && !@empresa_id.to_s.empty?
          query.all
        rescue
          []
        end

        # ========================================
        # EVOLUÇÃO 6 MESES (receita real vs despesas)
        # ========================================
        @evolucao = []
        hoje = Date.today
        6.times do |i|
          d = hoje << i
          m_inicio = Date.new(d.year, d.month, 1)
          m_fim = (m_inicio >> 1) - 1
          m_base = db[:movimentacoes].where(data_movimentacao: m_inicio..m_fim, status: %w[confirmado conciliado pendente]).exclude(tipo_operacao: 'transferencia')
          m_base = m_base.where(empresa_id: @empresa_id.to_i) if @empresa_id && !@empresa_id.to_s.empty?
          rec = (m_base.where(tipo: 'receita').exclude(is_antecipacao: true).sum(:lucro) || 0).to_f
          desp = (m_base.where(tipo: 'despesa').exclude(is_antecipacao: true).sum(:valor_bruto) || 0).to_f
          antecip = (m_base.where(tipo: 'receita', is_antecipacao: true).sum(:valor_bruto) || 0).to_f
          @evolucao.unshift({ mes: "#{nome_mes(d.month)[0..2]}/#{d.year}", receita_real: rec, despesas: desp, antecipacoes: antecip, resultado: rec + antecip - desp })
        end

        erb :'fluxo_caixa/index', layout: :'layouts/application'
      end
    end
  end
end
