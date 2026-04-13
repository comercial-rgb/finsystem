# frozen_string_literal: true
# controllers/despesas_controller.rb - Despesas reais da empresa (exclui repasses/transferências)

module FinSystem
  module Controllers
    class DespesasController < Sinatra::Base
      helpers Middleware::Auth::AuthHelpers
      helpers Helpers::ViewHelpers

      set :views, File.join(File.dirname(__FILE__), '..', 'views')
      set :raise_errors, true

      before { autenticar_requisicao }

      # ========================================
      # LISTAGEM DE DESPESAS REAIS
      # ========================================
      get '/despesas' do
        @mes = (params[:mes] || Date.today.month).to_i
        @ano = (params[:ano] || Date.today.year).to_i
        @empresa_id = params[:empresa_id]
        @conta_bancaria_id = params[:conta_bancaria_id]
        @status = params[:status]
        @busca = params[:busca]
        @tipo_operacao = params[:tipo_operacao]
        @page = (params[:page] || 1).to_i
        @per_page = 25

        @empresas = Models::Empresa.todas
        @contas = Models::Empresa.todas_contas

        filtros = {
          mes: @mes, ano: @ano, empresa_id: @empresa_id,
          tipo: 'despesa', conta_bancaria_id: @conta_bancaria_id,
          status: @status, busca: @busca
        }

        all_movimentacoes = Models::Movimentacao.listar(filtros)

        # Excluir repasses, antecipações e transferências — mostrar apenas despesas reais
        all_movimentacoes = all_movimentacoes.reject do |m|
          %w[repasse antecipacao transferencia].include?(m[:tipo_operacao])
        end

        # Filtrar por tipo de operação se selecionado
        if @tipo_operacao && !@tipo_operacao.empty?
          all_movimentacoes = all_movimentacoes.select { |m| m[:tipo_operacao] == @tipo_operacao }
        end

        # Totais (exclui cancelados)
        ativas = all_movimentacoes.reject { |m| m[:status] == 'cancelado' }
        @total_despesas = ativas.sum { |m| m[:valor_bruto] || 0 }
        @total_registros = all_movimentacoes.size
        @total_pages = (@total_registros / @per_page.to_f).ceil
        @total_pages = 1 if @total_pages < 1

        # Totais por categoria
        @por_categoria = ativas.group_by { |m| m[:categoria_nome] || 'Sem categoria' }.map do |cat, movs|
          { categoria: cat, total: movs.sum { |m| m[:valor_bruto] || 0 }, qtd: movs.size }
        end.sort_by { |c| -c[:total] }

        # Paginar
        offset = (@page - 1) * @per_page
        @movimentacoes = all_movimentacoes[offset, @per_page] || []

        erb :'despesas/index', layout: :'layouts/application'
      end
    end
  end
end
