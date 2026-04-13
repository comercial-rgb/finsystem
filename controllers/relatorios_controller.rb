# frozen_string_literal: true
# controllers/relatorios_controller.rb - Relatórios e exportação

module FinSystem
  module Controllers
    class RelatoriosController < Sinatra::Base
      helpers Middleware::Auth::AuthHelpers
      helpers Helpers::ViewHelpers

      set :views, File.join(File.dirname(__FILE__), '..', 'views')
      set :raise_errors, true

      before { autenticar_requisicao }

      # Relatório consolidado
      get '/relatorios' do
        requer_nivel('financeiro')

        @mes = (params[:mes] || Date.today.month).to_i
        @ano = (params[:ano] || Date.today.year).to_i
        @empresas = Models::Empresa.todas

        @resumos = @empresas.map do |emp|
          resumo = Models::Movimentacao.resumo_mensal(emp[:id], @mes, @ano)
          resultado = resumo[:total_receitas] - resumo[:total_despesas]
          distribuicao = Models::Empresa.distribuicao_lucro(emp[:id], resultado > 0 ? resultado : 0)
          {
            empresa: emp,
            resumo: resumo,
            resultado: resultado,
            distribuicao: distribuicao
          }
        end

        # Consolidado geral
        @total_geral = {
          receitas: @resumos.sum { |r| r[:resumo][:total_receitas] },
          despesas: @resumos.sum { |r| r[:resumo][:total_despesas] },
          resultado: @resumos.sum { |r| r[:resultado] }
        }

        erb :'relatorios/index', layout: :'layouts/application'
      end

      # Exportar CSV de movimentações para conciliação bancária
      get '/relatorios/exportar_csv' do
        requer_nivel('financeiro')

        filtros = {
          mes: params[:mes], ano: params[:ano],
          empresa_id: params[:empresa_id],
          conta_bancaria_id: params[:conta_bancaria_id]
        }

        movimentacoes = Models::Movimentacao.listar(filtros)

        content_type 'text/csv; charset=utf-8'
        attachment "movimentacoes_#{params[:mes]}_#{params[:ano]}.csv"

        csv = "Data;Tipo;Descrição;Valor Bruto;Valor Líquido;Lucro;Categoria;Cliente/Fornecedor;Banco;Status;Conciliado;Ref. Banco;Documento\n"
        movimentacoes.each do |m|
          csv += [
            m[:data_movimentacao],
            m[:tipo]&.upcase,
            "\"#{m[:descricao]}\"",
            m[:valor_bruto],
            m[:valor_liquido],
            m[:lucro],
            "\"#{m[:categoria_nome]}\"",
            "\"#{m[:cliente_nome] || m[:fornecedor_nome]}\"",
            "\"#{m[:banco_nome]}\"",
            m[:status],
            m[:conciliado] ? 'SIM' : 'NÃO',
            m[:referencia_banco],
            m[:numero_documento]
          ].join(';') + "\n"
        end
        csv
      end

      # Relatório de antecipações
      get '/relatorios/antecipacoes' do
        requer_nivel('financeiro')

        @mes = (params[:mes] || Date.today.month).to_i
        @ano = (params[:ano] || Date.today.year).to_i

        inicio = Date.new(@ano, @mes, 1)
        fim = (inicio >> 1) - 1

        @antecipacoes = FinSystem::Database.db[:movimentacoes]
          .where(is_antecipacao: true, data_movimentacao: inicio..fim)
          .left_join(:fornecedores, Sequel[:fornecedores][:id] => Sequel[:movimentacoes][:fornecedor_id])
          .left_join(:empresas, Sequel[:empresas][:id] => Sequel[:movimentacoes][:empresa_id])
          .select_all(:movimentacoes)
          .select_append(Sequel[:fornecedores][:nome].as(:fornecedor_nome))
          .select_append(Sequel[:empresas][:nome_fantasia].as(:empresa_nome))
          .order(:data_movimentacao)
          .all

        @total_antecipado = @antecipacoes.select { |a| a[:tipo] == 'despesa' }.sum { |a| a[:valor_bruto] || 0 }
        @total_lucro = @antecipacoes.select { |a| a[:tipo] == 'receita' }.sum { |a| a[:valor_bruto] || 0 }

        erb :'relatorios/antecipacoes', layout: :'layouts/application'
      end
    end
  end
end
