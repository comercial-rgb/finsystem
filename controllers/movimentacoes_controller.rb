# frozen_string_literal: true
# controllers/movimentacoes_controller.rb - CRUD de movimentações financeiras

module FinSystem
  module Controllers
    class MovimentacoesController < Sinatra::Base
      helpers Middleware::Auth::AuthHelpers
      helpers Helpers::ViewHelpers

      set :views, File.join(File.dirname(__FILE__), '..', 'views')
      set :raise_errors, true

      before { autenticar_requisicao }

      # ========================================
      # LISTAGEM COM FILTROS
      # ========================================
      get '/movimentacoes' do
        @mes = (params[:mes] || Date.today.month).to_i
        @ano = (params[:ano] || Date.today.year).to_i
        @empresa_id = params[:empresa_id]
        @tipo = params[:tipo]
        @conta_bancaria_id = params[:conta_bancaria_id]
        @status = params[:status]
        @busca = params[:busca]
        @page = (params[:page] || 1).to_i
        @per_page = 25

        @empresas = Models::Empresa.todas
        @contas = Models::Empresa.todas_contas

        filtros = {
          mes: @mes, ano: @ano, empresa_id: @empresa_id,
          tipo: @tipo, conta_bancaria_id: @conta_bancaria_id,
          status: @status, busca: @busca
        }

        all_movimentacoes = Models::Movimentacao.listar(filtros)

        # Totais dos filtros atuais (exclui cancelados e transferências do cálculo de saldo)
        ativas = all_movimentacoes.reject { |m| %w[cancelado transferencia].include?(m[:status]) || m[:tipo_operacao] == 'transferencia' }
        @total_receitas = ativas.select { |m| m[:tipo] == 'receita' }.sum { |m| m[:valor_bruto] || 0 }
        @total_despesas = ativas.select { |m| m[:tipo] == 'despesa' }.sum { |m| m[:valor_bruto] || 0 }
        @saldo_periodo = @total_receitas - @total_despesas
        @total_registros = all_movimentacoes.size
        @total_pages = (@total_registros / @per_page.to_f).ceil

        # Paginar
        offset = (@page - 1) * @per_page
        @movimentacoes = all_movimentacoes[offset, @per_page] || []

        erb :'movimentacoes/index', layout: :'layouts/application'
      end

      # ========================================
      # TRANSFERÊNCIA ENTRE CONTAS
      # ========================================
      get '/movimentacoes/transferencia' do
        @empresas = Models::Empresa.todas
        @contas = Models::Empresa.todas_contas
        @transferencias = Models::Movimentacao.transferencias

        erb :'movimentacoes/transferencia', layout: :'layouts/application'
      end

      post '/movimentacoes/transferencia' do
        begin
          params[:usuario_id] = usuario_logado[:id]
          Models::Movimentacao.criar_transferencia(params)

          Models::AuditLog.registrar(
            usuario_id: usuario_logado[:id],
            acao: 'create',
            entidade: 'transferencia',
            detalhes: "Transferência: #{params[:valor]} de conta #{params[:conta_origem_id]} para #{params[:conta_destino_id]}",
            ip: request.ip
          )

          session[:flash_message] = 'Transferência realizada com sucesso! Saldos atualizados.'
          redirect '/movimentacoes/transferencia'
        rescue StandardError => e
          session[:flash_error] = "Erro na transferência: #{e.message}"
          redirect '/movimentacoes/transferencia'
        end
      end

      # ========================================
      # NOVA MOVIMENTAÇÃO
      # ========================================
      get '/movimentacoes/nova' do
        @empresas = Models::Empresa.todas
        @contas = Models::Empresa.todas_contas
        @categorias_receita = FinSystem::Database.db[:categorias].where(tipo: 'receita', ativo: true).all
        @categorias_despesa = FinSystem::Database.db[:categorias].where(tipo: 'despesa', ativo: true).all
        @clientes = FinSystem::Database.db[:clientes].where(ativo: true).order(:nome).all
        @fornecedores = FinSystem::Database.db[:fornecedores].where(ativo: true).order(:nome).all
        @socios = FinSystem::Database.db[:socios].where(ativo: true).order(:nome).all

        erb :'movimentacoes/form', layout: :'layouts/application'
      end

      # ========================================
      # CRIAR MOVIMENTAÇÃO
      # ========================================
      post '/movimentacoes' do
        begin
          params[:usuario_id] = usuario_logado[:id]

          # Validar valor_bruto obrigatório (exceto antecipações que usam campos próprios)
          if params[:is_antecipacao] != 'true' && params[:valor_bruto].to_s.strip.empty?
            session[:flash_error] = 'O valor bruto é obrigatório.'
            redirect '/movimentacoes/nova'
            return
          end

          if params[:is_antecipacao] == 'true'
            # Fluxo de antecipação: gera 2 movimentações automaticamente
            fornecedor = FinSystem::Database.db[:fornecedores].where(id: params[:fornecedor_id].to_i).first
            Models::Movimentacao.criar_antecipacao(
              empresa_id: params[:empresa_id],
              conta_bancaria_id: params[:conta_bancaria_id],
              fornecedor_id: params[:fornecedor_id],
              fornecedor_nome: fornecedor ? fornecedor[:nome] : 'Fornecedor',
              usuario_id: usuario_logado[:id],
              data_movimentacao: params[:data_movimentacao],
              valor_original: params[:valor_original_faturamento],
              valor_antecipado: params[:valor_antecipado],
              taxa: params[:taxa_antecipacao],
              categoria_despesa_id: params[:categoria_id],
              categoria_receita_id: FinSystem::Database.db[:categorias].where(subtipo: 'antecipacao').first&.dig(:id),
              forma_pagamento: params[:forma_pagamento],
              observacoes: params[:observacoes]
            )
          else
            id = Models::Movimentacao.criar(params)

            # Upload de comprovante se enviado
            if params[:comprovante] && params[:comprovante][:tempfile]
              Models::Comprovante.salvar(id, usuario_logado[:id], params[:comprovante])
            end
          end

          Models::AuditLog.registrar(
            usuario_id: usuario_logado[:id],
            acao: 'create',
            entidade: 'movimentacao',
            detalhes: "#{params[:tipo]}: #{params[:descricao]} - #{params[:valor_bruto]}",
            ip: request.ip
          )

          session[:flash_message] = 'Movimentação registrada com sucesso!'
          redirect '/movimentacoes'
        rescue StandardError => e
          session[:flash_error] = "Erro ao criar movimentação: #{e.message}"
          redirect '/movimentacoes/nova'
        end
      end

      # ========================================
      # EDITAR MOVIMENTAÇÃO
      # ========================================
      get '/movimentacoes/:id/editar' do
        @movimentacao = Models::Movimentacao.find(params[:id].to_i)
        halt 404, 'Movimentação não encontrada' unless @movimentacao

        @empresas = Models::Empresa.todas
        @contas = Models::Empresa.todas_contas
        @categorias_receita = FinSystem::Database.db[:categorias].where(tipo: 'receita', ativo: true).all
        @categorias_despesa = FinSystem::Database.db[:categorias].where(tipo: 'despesa', ativo: true).all
        @clientes = FinSystem::Database.db[:clientes].where(ativo: true).order(:nome).all
        @fornecedores = FinSystem::Database.db[:fornecedores].where(ativo: true).order(:nome).all
        @comprovantes = Models::Comprovante.por_movimentacao(params[:id].to_i)
        @socios = FinSystem::Database.db[:socios].where(ativo: true).order(:nome).all

        erb :'movimentacoes/edit', layout: :'layouts/application'
      end

      # Atualizar
      put '/movimentacoes/:id' do
        # Se o tipo veio como 'antecipacao', converter para despesa + flag
        if params[:tipo] == 'antecipacao'
          params[:tipo] = 'despesa'
          params[:is_antecipacao] = 'true'
        end

        Models::Movimentacao.atualizar(params[:id].to_i, params)

        # Upload de novo comprovante
        if params[:comprovante] && params[:comprovante][:tempfile]
          Models::Comprovante.salvar(params[:id].to_i, usuario_logado[:id], params[:comprovante])
        end

        Models::AuditLog.registrar(
          usuario_id: usuario_logado[:id],
          acao: 'update',
          entidade: 'movimentacao',
          entidade_id: params[:id].to_i,
          ip: request.ip
        )

        session[:flash_message] = 'Movimentação atualizada!'
        redirect '/movimentacoes'
      end

      # Excluir
      delete '/movimentacoes/:id' do
        Models::Movimentacao.excluir(params[:id].to_i)

        Models::AuditLog.registrar(
          usuario_id: usuario_logado[:id],
          acao: 'delete',
          entidade: 'movimentacao',
          entidade_id: params[:id].to_i,
          ip: request.ip
        )

        session[:flash_message] = 'Movimentação excluída!'
        redirect '/movimentacoes'
      end

      # ========================================
      # CONCILIAÇÃO BANCÁRIA
      # ========================================
      post '/movimentacoes/:id/conciliar' do
        Models::Movimentacao.conciliar(params[:id].to_i, params[:referencia_banco])
        session[:flash_message] = 'Movimentação conciliada!'
        redirect back
      end

      # ========================================
      # CONFIRMAR MOVIMENTAÇÃO (pendente → confirmado, atualiza saldo)
      # ========================================
      post '/movimentacoes/:id/confirmar' do
        mov = Models::Movimentacao.find(params[:id].to_i)
        halt 404 unless mov

        Models::Movimentacao.confirmar(params[:id].to_i)

        Models::AuditLog.registrar(
          usuario_id: usuario_logado[:id],
          acao: 'confirm',
          entidade: 'movimentacao',
          entidade_id: params[:id].to_i,
          detalhes: "Movimentação confirmada: #{mov[:descricao]} - R$ #{mov[:valor_bruto]}",
          ip: request.ip
        )

        session[:flash_message] = 'Movimentação confirmada! Saldo atualizado.'
        redirect back
      end

      # ========================================
      # MARCAR COMO PAGO
      # ========================================
      post '/movimentacoes/:id/marcar_pago' do
        mov = Models::Movimentacao.find(params[:id].to_i)
        halt 404 unless mov

        update = { pago: true, status: 'confirmado', updated_at: Time.now }

        # Se recorrente, criar a próxima ocorrência
        if mov[:tipo_cobranca] == 'recorrente'
          dia = mov[:dia_vencimento_recorrente] || mov[:data_proximo_vencimento]&.day || 10
          prox = mov[:data_proximo_vencimento] ? mov[:data_proximo_vencimento] >> 1 : Date.today >> 1
          prox_data = Date.new(prox.year, prox.month, [dia, Date.new(prox.year, prox.month, -1).day].min)

          # Criar nova movimentação para o próximo mês
          FinSystem::Database.db[:movimentacoes].insert(
            empresa_id: mov[:empresa_id],
            conta_bancaria_id: mov[:conta_bancaria_id],
            categoria_id: mov[:categoria_id],
            fornecedor_id: mov[:fornecedor_id],
            cliente_id: mov[:cliente_id],
            usuario_id: usuario_logado[:id],
            tipo: mov[:tipo],
            data_movimentacao: prox_data,
            data_competencia: prox_data,
            descricao: mov[:descricao].gsub(/ \(\d+\/\d+\)/, ''),
            valor_bruto: mov[:valor_bruto],
            valor_liquido: mov[:valor_liquido],
            tipo_operacao: mov[:tipo_operacao],
            forma_pagamento: mov[:forma_pagamento],
            status: 'pendente',
            tipo_cobranca: 'recorrente',
            dia_vencimento_recorrente: dia,
            data_proximo_vencimento: prox_data,
            pago: false,
            recorrencia_pai_id: mov[:recorrencia_pai_id] || mov[:id],
            observacoes: mov[:observacoes]
          )
        end

        FinSystem::Database.db[:movimentacoes].where(id: params[:id].to_i).update(update)

        # Atualizar saldo da conta bancária
        Models::Movimentacao.atualizar_saldo_conta(mov[:conta_bancaria_id])
        Models::Movimentacao.registrar_historico_saldo(mov[:conta_bancaria_id], Date.today, 'movimentacao', mov[:id], "Pago: #{mov[:descricao]}")

        session[:flash_message] = 'Pagamento marcado como realizado!'
        redirect back
      end

      # ========================================
      # COMPROVANTES
      # ========================================
      # Upload avulso de comprovante
      post '/movimentacoes/:id/comprovante' do
        if params[:comprovante] && params[:comprovante][:tempfile]
          resultado = Models::Comprovante.salvar(params[:id].to_i, usuario_logado[:id], params[:comprovante])
          if resultado.is_a?(Hash) && resultado[:error]
            session[:flash_error] = resultado[:error]
          else
            session[:flash_message] = 'Comprovante anexado!'
          end
        end
        redirect "/movimentacoes/#{params[:id]}/editar"
      end

      # Download de comprovante
      get '/comprovantes/:id/download' do
        comp = FinSystem::Database.db[:comprovantes].where(id: params[:id].to_i).first
        halt 404 unless comp && File.exist?(comp[:caminho_arquivo])

        send_file comp[:caminho_arquivo],
                  filename: comp[:nome_original],
                  type: "application/#{comp[:tipo_arquivo]}"
      end

      # Excluir comprovante
      delete '/comprovantes/:id' do
        comp = FinSystem::Database.db[:comprovantes].where(id: params[:id].to_i).first
        halt 404 unless comp

        mov_id = comp[:movimentacao_id]
        Models::Comprovante.excluir(params[:id].to_i)
        session[:flash_message] = 'Comprovante removido!'
        redirect "/movimentacoes/#{mov_id}/editar"
      end

      # ========================================
      # CLIENTES / FORNECEDORES (Quick CRUD)
      # ========================================
      post '/clientes' do
        FinSystem::Database.db[:clientes].insert(
          empresa_id: params[:empresa_id]&.to_i,
          nome: params[:nome],
          cnpj_cpf_ein: params[:cnpj_cpf_ein],
          tipo: params[:tipo_pessoa] || 'PJ',
          email: params[:email],
          telefone: params[:telefone],
          pais: params[:pais] || 'BR'
        )
        session[:flash_message] = "Cliente #{params[:nome]} cadastrado!"
        redirect back
      end

      post '/fornecedores' do
        FinSystem::Database.db[:fornecedores].insert(
          empresa_id: params[:empresa_id]&.to_i,
          nome: params[:nome],
          cnpj_cpf_ein: params[:cnpj_cpf_ein],
          tipo: params[:tipo_fornecedor] || 'rede_credenciada',
          categoria: params[:categoria_fornecedor],
          email: params[:email],
          telefone: params[:telefone],
          pais: params[:pais] || 'BR'
        )
        session[:flash_message] = "Fornecedor #{params[:nome]} cadastrado!"
        redirect back
      end

      # ========================================
      # CONSULTA CNPJ VIA BRASILAPI
      # ========================================
      get '/api/consultar_cnpj/:cnpj' do
        content_type :json
        halt 401, { error: 'Não autorizado' }.to_json unless usuario_logado
        cnpj = params[:cnpj]&.gsub(/\D/, '')
        halt 422, { success: false, message: 'CNPJ inválido' }.to_json unless cnpj&.length == 14

        require 'net/http'
        require 'uri'
        begin
          uri = URI("https://brasilapi.com.br/api/cnpj/v1/#{cnpj}")
          http = Net::HTTP.new(uri.host, uri.port)
          http.use_ssl = true
          http.open_timeout = 5
          http.read_timeout = 10
          response = http.get(uri.request_uri)

          if response.code == '200'
            dados = JSON.parse(response.body)
            {
              success: true,
              data: {
                razao_social: dados['razao_social'],
                nome_fantasia: dados['nome_fantasia'],
                cnpj: dados['cnpj'],
                logradouro: [dados['logradouro'], dados['numero'], dados['complemento']].compact.reject(&:empty?).join(', '),
                bairro: dados['bairro'],
                municipio: dados['municipio'],
                uf: dados['uf'],
                cep: dados['cep'],
                telefone: dados['ddd_telefone_1'],
                email: dados['email'],
                situacao_cadastral: dados['descricao_situacao_cadastral']
              }
            }.to_json
          else
            { success: false, message: 'CNPJ não encontrado na Receita Federal' }.to_json
          end
        rescue Net::OpenTimeout, Net::ReadTimeout
          { success: false, message: 'Timeout ao consultar BrasilAPI' }.to_json
        rescue => e
          { success: false, message: "Erro na consulta: #{e.message}" }.to_json
        end
      end
    end
  end
end
