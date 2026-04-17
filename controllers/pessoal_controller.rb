# frozen_string_literal: true
# controllers/pessoal_controller.rb - Módulo de finanças pessoais

module FinSystem
  module Controllers
    class PessoalController < Sinatra::Base
      helpers Middleware::Auth::AuthHelpers
      helpers Helpers::ViewHelpers

      set :views, File.join(File.dirname(__FILE__), '..', 'views')
      set :raise_errors, true

      before { autenticar_requisicao }

      # Dashboard pessoal
      get '/pessoal' do
        @mes = (params[:mes] || Date.today.month).to_i
        @ano = (params[:ano] || Date.today.year).to_i
        @page = (params[:page] || 1).to_i
        @per_page = 20

        @resumo = Models::Pessoal.resumo(usuario_logado[:id], @mes, @ano) || {}
        all_movimentacoes = Models::Pessoal.listar_movimentacoes(
          usuario_logado[:id], { mes: @mes, ano: @ano }
        ) || []
        @categorias = Models::Pessoal.categorias(usuario_logado[:id]) || []

        # Contas bancárias pessoais
        @contas = Models::Pessoal.saldo_por_conta_pessoal(usuario_logado[:id]) || []

        # Paginação
        @total_registros = all_movimentacoes.size
        @total_pages = (@total_registros / @per_page.to_f).ceil
        offset = (@page - 1) * @per_page
        @movimentacoes = all_movimentacoes[offset, @per_page] || []

        # Dados para gráfico
        @evolucao = _dados_evolucao_pessoal(usuario_logado[:id])

        erb :'pessoal/index', layout: :'layouts/application'
      end

      # Nova movimentação pessoal
      get '/pessoal/nova' do
        @categorias = Models::Pessoal.categorias(usuario_logado[:id])
        @movimentacao = {}
        erb :'pessoal/form', layout: :'layouts/application'
      end

      # Criar movimentação pessoal
      post '/pessoal' do
        params[:usuario_id] = usuario_logado[:id]

        errors = Services::Validation.validate_pessoal(params)
        unless errors.empty?
          session[:flash_error] = errors.join(', ')
          redirect '/pessoal/nova'
          return
        end

        id = Models::Pessoal.criar_movimentacao(params)

        # Upload de comprovante
        if params[:comprovante] && params[:comprovante][:tempfile]
          Models::Pessoal.salvar_comprovante(id, params[:comprovante])
        end

        session[:flash_message] = 'Lançamento pessoal registrado!'
        redirect '/pessoal'
      end

      # Editar movimentação pessoal
      get '/pessoal/:id/editar' do
        @movimentacao = Models::Pessoal.find_movimentacao(params[:id].to_i)
        halt 403 unless @movimentacao && @movimentacao[:usuario_id] == usuario_logado[:id]

        @categorias = Models::Pessoal.categorias(usuario_logado[:id])
        @comprovantes = Models::Pessoal.comprovantes_por_movimentacao(params[:id].to_i)
        erb :'pessoal/edit', layout: :'layouts/application'
      end

      # Atualizar movimentação pessoal
      put '/pessoal/:id' do
        mov = Models::Pessoal.find_movimentacao(params[:id].to_i)
        halt 403 unless mov && mov[:usuario_id] == usuario_logado[:id]

        Models::Pessoal.atualizar_movimentacao(params[:id].to_i, params)

        # Upload de novo comprovante
        if params[:comprovante] && params[:comprovante][:tempfile]
          Models::Pessoal.salvar_comprovante(params[:id].to_i, params[:comprovante])
        end

        session[:flash_message] = 'Lançamento pessoal atualizado!'
        redirect '/pessoal'
      end

      # Excluir movimentação pessoal
      delete '/pessoal/:id' do
        mov = Models::Pessoal.find_movimentacao(params[:id].to_i)
        halt 403 unless mov && mov[:usuario_id] == usuario_logado[:id]

        Models::Pessoal.excluir_movimentacao(params[:id].to_i)
        session[:flash_message] = 'Lançamento pessoal excluído!'
        redirect '/pessoal'
      end

      # Upload comprovante avulso para pessoal
      post '/pessoal/:id/comprovante' do
        mov = Models::Pessoal.find_movimentacao(params[:id].to_i)
        halt 403 unless mov && mov[:usuario_id] == usuario_logado[:id]

        if params[:comprovante] && params[:comprovante][:tempfile]
          resultado = Models::Pessoal.salvar_comprovante(params[:id].to_i, params[:comprovante])
          if resultado.is_a?(Hash) && resultado[:error]
            session[:flash_error] = resultado[:error]
          else
            session[:flash_message] = 'Comprovante anexado!'
          end
        end
        redirect "/pessoal/#{params[:id]}/editar"
      end

      # Download comprovante pessoal
      get '/pessoal/comprovantes/:id/download' do
        comp = FinSystem::Database.db[:pessoal_comprovantes].where(id: params[:id].to_i).first
        halt 404 unless comp && File.exist?(comp[:caminho_arquivo])

        send_file comp[:caminho_arquivo],
                  filename: comp[:nome_original],
                  type: 'application/octet-stream'
      end

      # Excluir comprovante pessoal
      delete '/pessoal/comprovantes/:id' do
        mov_id = Models::Pessoal.excluir_comprovante(params[:id].to_i)
        session[:flash_message] = 'Comprovante removido!'
        redirect "/pessoal/#{mov_id}/editar"
      end

      # Criar categoria pessoal
      post '/pessoal/categorias' do
        params[:usuario_id] = usuario_logado[:id]
        Models::Pessoal.criar_categoria(params)
        session[:flash_message] = 'Categoria criada!'
        redirect '/pessoal'
      end

      # ========================================
      # CONTAS BANCÁRIAS PESSOAIS
      # ========================================
      # Criar conta bancária pessoal
      post '/pessoal/contas' do
        params[:usuario_id] = usuario_logado[:id]
        Models::Pessoal.criar_conta_bancaria(params)
        session[:flash_message] = 'Conta bancária cadastrada!'
        redirect '/pessoal'
      end

      # Atualizar saldo de conta bancária pessoal
      put '/pessoal/contas/:id/saldo' do
        conta = FinSystem::Database.db[:pessoal_contas_bancarias].where(id: params[:id].to_i).first
        halt 403 unless conta && conta[:usuario_id] == usuario_logado[:id]

        Models::Pessoal.atualizar_saldo_conta(params[:id].to_i, params[:saldo_inicial])
        session[:flash_message] = 'Saldo atualizado!'
        redirect '/pessoal'
      end

      # Excluir conta bancária pessoal
      delete '/pessoal/contas/:id' do
        conta = FinSystem::Database.db[:pessoal_contas_bancarias].where(id: params[:id].to_i).first
        halt 403 unless conta && conta[:usuario_id] == usuario_logado[:id]

        Models::Pessoal.excluir_conta_bancaria(params[:id].to_i)
        session[:flash_message] = 'Conta bancária removida!'
        redirect '/pessoal'
      end

      private

      def _dados_evolucao_pessoal(usuario_id)
        resultado = []
        hoje = Date.today
        6.times do |i|
          d = hoje << i
          inicio = Date.new(d.year, d.month, 1)
          fim = (inicio >> 1) - 1
          base = FinSystem::Database.db[:pessoal_movimentacoes].where(usuario_id: usuario_id, data_movimentacao: inicio..fim)
          rec = (base.where(tipo: 'receita').sum(:valor) || 0).to_f
          desp = (base.where(tipo: 'despesa').sum(:valor) || 0).to_f
          inv = (base.where(tipo: 'investimento').sum(:valor) || 0).to_f
          resultado.unshift({ mes: "#{nome_mes(d.month)[0..2]}/#{d.year}", receitas: rec, despesas: desp, investimentos: inv })
        end
        resultado
      end
    end
  end
end
