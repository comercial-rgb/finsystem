# frozen_string_literal: true
# controllers/empresas_controller.rb - Gestão de empresas, sócios e contas

module FinSystem
  module Controllers
    class EmpresasController < Sinatra::Base
      helpers Middleware::Auth::AuthHelpers
      helpers Helpers::ViewHelpers

      set :views, File.join(File.dirname(__FILE__), '..', 'views')
      set :raise_errors, true

      before { autenticar_requisicao }

      # Listar empresas
      get '/empresas' do
        requer_nivel('gerente')
        @empresas = Models::Empresa.todas.map do |emp|
          {
            empresa: emp,
            socios: Models::Empresa.socios(emp[:id]),
            contas: Models::Empresa.contas_bancarias(emp[:id])
          }
        end
        erb :'empresas/index', layout: :'layouts/application'
      end

      # Detalhes da empresa
      get '/empresas/:id' do
        requer_nivel('gerente')
        @empresa = Models::Empresa.find(params[:id].to_i)
        halt 404 unless @empresa

        @socios = Models::Empresa.socios(params[:id].to_i) || []
        @contas = Models::Empresa.contas_bancarias(params[:id].to_i) || []

        # Resumo financeiro do mês atual
        @mes = (params[:mes] || Date.today.month).to_i
        @ano = (params[:ano] || Date.today.year).to_i
        @resumo = Models::Movimentacao.resumo_mensal(params[:id], @mes, @ano) || {}
        @resultado = (@resumo[:total_receitas] || 0) - (@resumo[:despesas_operacionais] || 0)

        # Distribuição de lucros
        @distribuicao = Models::Empresa.distribuicao_lucro(params[:id].to_i, @resultado > 0 ? @resultado : 0)

        erb :'empresas/show', layout: :'layouts/application'
      end

      # Atualizar empresa
      put '/empresas/:id' do
        requer_nivel('admin')
        Models::Empresa.atualizar(params[:id].to_i, params)
        session[:flash_message] = 'Empresa atualizada!'
        redirect "/empresas/#{params[:id]}"
      end

      # Criar empresa
      post '/empresas' do
        requer_nivel('admin')
        Models::Empresa.criar(params)
        session[:flash_message] = 'Empresa cadastrada!'
        redirect '/empresas'
      end

      # ========================================
      # SÓCIOS
      # ========================================
      post '/empresas/:id/socios' do
        requer_nivel('admin')
        params[:empresa_id] = params[:id]
        Models::Empresa.criar_socio(params)
        session[:flash_message] = 'Sócio cadastrado!'
        redirect "/empresas/#{params[:id]}"
      end

      put '/socios/:id' do
        requer_nivel('admin')
        Models::Empresa.atualizar_socio(params[:id].to_i, params)
        session[:flash_message] = 'Sócio atualizado!'
        redirect back
      end

      # ========================================
      # CONTAS BANCÁRIAS
      # ========================================
      post '/empresas/:id/contas' do
        requer_nivel('gerente')
        saldo_str = params[:saldo_inicial].to_s.strip
        saldo_str = '0' if saldo_str.empty?
        FinSystem::Database.db[:contas_bancarias].insert(
          empresa_id: params[:id].to_i,
          banco: params[:banco],
          agencia: params[:agencia],
          conta: params[:conta],
          tipo_conta: params[:tipo_conta] || 'corrente',
          moeda: params[:moeda] || 'BRL',
          saldo_inicial: BigDecimal(saldo_str.gsub('.', '').gsub(',', '.')),
          apelido: params[:apelido]
        )
        session[:flash_message] = 'Conta bancária cadastrada!'
        redirect "/empresas/#{params[:id]}"
      end

      # Atualizar saldo inicial de conta bancária
      put '/contas/:id/saldo' do
        requer_nivel('gerente')
        saldo_str = params[:saldo_inicial].to_s.strip
        saldo_str = '0' if saldo_str.empty?
        FinSystem::Database.db[:contas_bancarias].where(id: params[:id].to_i).update(
          saldo_inicial: BigDecimal(saldo_str.gsub('.', '').gsub(',', '.'))
        )
        Models::Movimentacao.atualizar_saldo_conta(params[:id].to_i)
        session[:flash_message] = 'Saldo inicial atualizado!'
        redirect back
      end

      # Calibrar saldo: dado o saldo real de hoje, recalcula saldo_inicial
      # para que saldo_inicial + movimentações = saldo_real_hoje
      post '/contas/:id/calibrar-saldo' do
        db  = FinSystem::Database.db
        id  = params[:id].to_i
        conta = db[:contas_bancarias].where(id: id).first
        halt 404, 'Conta não encontrada' unless conta

        saldo_real_str = params[:saldo_real_hoje].to_s.strip.gsub('.', '').gsub(',', '.')
        saldo_real = BigDecimal(saldo_real_str)

        # Soma de entradas e saídas das movimentações confirmadas
        movs = db[:movimentacoes].where(
          conta_bancaria_id: id,
          status: %w[confirmado conciliado transferencia]
        )
        entradas = movs.where(tipo: 'receita').sum(:valor_bruto) || 0
        saidas   = movs.where(tipo: 'despesa').sum(:valor_bruto) || 0

        # saldo_inicial = saldo_real - entradas + saidas
        novo_saldo_inicial = saldo_real - entradas + saidas

        db[:contas_bancarias].where(id: id).update(
          saldo_inicial: novo_saldo_inicial,
          saldo_atual:   saldo_real
        )

        Models::AuditLog.registrar(
          usuario_id: usuario_logado[:id],
          acao: 'update',
          entidade: 'conta_bancaria',
          entidade_id: id,
          detalhes: "Calibração de saldo: real=#{saldo_real}, novo saldo_inicial=#{novo_saldo_inicial}",
          ip: request.ip
        )

        session[:flash_message] = "Saldo calibrado! Saldo inicial ajustado para #{fmt_moeda(novo_saldo_inicial)} para bater com o saldo real de #{fmt_moeda(saldo_real)}."
        redirect back
      end
    end
  end
end
