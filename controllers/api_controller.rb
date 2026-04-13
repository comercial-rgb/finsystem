# frozen_string_literal: true
# controllers/api_controller.rb - API JSON para integração entre sistemas

module FinSystem
  module Controllers
    class ApiController < Sinatra::Base
      helpers Helpers::ViewHelpers

      set :views, File.join(File.dirname(__FILE__), '..', 'views')

      before do
        content_type :json
        autenticar_api
      end

      # ========================================
      # AUTENTICAÇÃO POR API KEY
      # ========================================
      def autenticar_api
        api_key = request.env['HTTP_X_API_KEY'] || params[:api_key]
        expected = ENV.fetch('FINSYSTEM_API_KEY') {
          'finsystem_dev_api_key_2026' # Apenas para desenvolvimento
        }

        unless api_key && Rack::Utils.secure_compare(api_key, expected)
          halt 401, { error: 'API key inválida ou ausente', code: 'UNAUTHORIZED' }.to_json
        end
      end

      # ========================================
      # CRIAR MOVIMENTAÇÃO VIA API
      # POST /api/movimentacoes
      # ========================================
      post '/api/movimentacoes' do
        begin
          dados = JSON.parse(request.body.read, symbolize_names: true)

          # Campos obrigatórios
          campos_obrigatorios = %i[empresa_id conta_bancaria_id tipo data_movimentacao descricao valor_bruto]
          faltando = campos_obrigatorios.select { |c| dados[c].nil? || dados[c].to_s.strip.empty? }

          unless faltando.empty?
            halt 422, {
              error: 'Campos obrigatórios faltando',
              campos: faltando,
              code: 'VALIDATION_ERROR'
            }.to_json
          end

          # Validar tipo
          unless %w[receita despesa].include?(dados[:tipo])
            halt 422, { error: 'Tipo deve ser "receita" ou "despesa"', code: 'VALIDATION_ERROR' }.to_json
          end

          # Validar empresa existe
          empresa = FinSystem::Database.db[:empresas].where(id: dados[:empresa_id].to_i, ativo: true).first
          unless empresa
            halt 422, { error: 'Empresa não encontrada', code: 'VALIDATION_ERROR' }.to_json
          end

          # Validar conta bancária existe
          conta = FinSystem::Database.db[:contas_bancarias].where(id: dados[:conta_bancaria_id].to_i, ativo: true).first
          unless conta
            halt 422, { error: 'Conta bancária não encontrada', code: 'VALIDATION_ERROR' }.to_json
          end

          # Buscar usuário de integração (ou primeiro admin)
          usuario_integracao = FinSystem::Database.db[:usuarios]
            .where(ativo: true, nivel_acesso: 'admin')
            .order(:id)
            .first

          unless usuario_integracao
            halt 500, { error: 'Nenhum usuário admin encontrado para integração', code: 'CONFIG_ERROR' }.to_json
          end

          # Montar params para o model
          # Converter valores numéricos (float/int) para formato BR que o model espera
          # O model faz gsub('.','').gsub(',','.') então precisamos enviar "39327,76" e não "39327.76"
          def formatar_valor_para_model(val)
            return nil if val.nil?
            # Se já tem vírgula (formato BR), retorna como está
            return val.to_s if val.to_s.include?(',')
            # Converte float/int para formato BR: 39327.76 -> "39327,76"
            format('%.2f', val.to_f).gsub('.', ',')
          end

          params_mov = {
            empresa_id: dados[:empresa_id].to_s,
            conta_bancaria_id: dados[:conta_bancaria_id].to_s,
            usuario_id: usuario_integracao[:id],
            tipo: dados[:tipo],
            data_movimentacao: dados[:data_movimentacao].to_s,
            descricao: dados[:descricao].to_s,
            valor_bruto: formatar_valor_para_model(dados[:valor_bruto]),
            valor_liquido: formatar_valor_para_model(dados[:valor_liquido]),
            lucro: formatar_valor_para_model(dados[:lucro]),
            categoria_id: dados[:categoria_id]&.to_s,
            cliente_id: dados[:cliente_id]&.to_s,
            fornecedor_id: dados[:fornecedor_id]&.to_s,
            tipo_operacao: dados[:tipo_operacao] || 'repasse',
            numero_documento: dados[:numero_documento]&.to_s,
            status: dados[:status] || 'confirmado',
            forma_pagamento: dados[:forma_pagamento],
            observacoes: dados[:observacoes],
            tipo_cobranca: dados[:tipo_cobranca] || 'unica',
            referencia_banco: dados[:referencia_externa]
          }

          id = Models::Movimentacao.criar(params_mov)

          # Registrar no audit log
          Models::AuditLog.registrar(
            usuario_id: usuario_integracao[:id],
            acao: 'create',
            entidade: 'movimentacao',
            detalhes: "API Integration: #{dados[:tipo]} - #{dados[:descricao]} - #{dados[:valor_bruto]} (ref: #{dados[:referencia_externa]})",
            ip: request.ip
          )

          # Retornar dados criados
          movimentacao = FinSystem::Database.db[:movimentacoes].where(id: id).first

          status 201
          {
            success: true,
            message: 'Movimentação criada com sucesso',
            data: {
              id: movimentacao[:id],
              tipo: movimentacao[:tipo],
              descricao: movimentacao[:descricao],
              valor_bruto: movimentacao[:valor_bruto].to_f,
              status: movimentacao[:status],
              data_movimentacao: movimentacao[:data_movimentacao].to_s,
              tipo_operacao: movimentacao[:tipo_operacao],
              referencia_banco: movimentacao[:referencia_banco]
            }
          }.to_json

        rescue JSON::ParserError
          halt 400, { error: 'JSON inválido no corpo da requisição', code: 'PARSE_ERROR' }.to_json
        rescue StandardError => e
          $stderr.puts "[API ERROR] #{e.class}: #{e.message}"
          $stderr.puts e.backtrace&.first(5)&.join("\n")
          halt 500, { error: "Erro interno: #{e.message}", code: 'INTERNAL_ERROR' }.to_json
        end
      end

      # ========================================
      # LISTAR EMPRESAS (para configuração)
      # GET /api/empresas
      # ========================================
      get '/api/empresas' do
        empresas = FinSystem::Database.db[:empresas].where(ativo: true).all.map do |e|
          {
            id: e[:id],
            razao_social: e[:razao_social],
            nome_fantasia: e[:nome_fantasia],
            cnpj_ein: e[:cnpj_ein]
          }
        end

        { success: true, data: empresas }.to_json
      end

      # ========================================
      # LISTAR CONTAS BANCÁRIAS (para configuração)
      # GET /api/contas
      # ========================================
      get '/api/contas' do
        contas = FinSystem::Database.db[:contas_bancarias].where(ativo: true).all.map do |c|
          empresa = FinSystem::Database.db[:empresas].where(id: c[:empresa_id]).first
          {
            id: c[:id],
            banco: c[:banco],
            agencia: c[:agencia],
            conta: c[:conta],
            apelido: c[:apelido],
            moeda: c[:moeda],
            empresa_id: c[:empresa_id],
            empresa_nome: empresa&.dig(:nome_fantasia)
          }
        end

        { success: true, data: contas }.to_json
      end

      # ========================================
      # LISTAR FORNECEDORES (para mapeamento)
      # GET /api/fornecedores
      # ========================================
      get '/api/fornecedores' do
        fornecedores = FinSystem::Database.db[:fornecedores].where(ativo: true).order(:nome).all.map do |f|
          {
            id: f[:id],
            nome: f[:nome],
            cnpj_cpf_ein: f[:cnpj_cpf_ein],
            empresa_id: f[:empresa_id]
          }
        end

        { success: true, data: fornecedores }.to_json
      end

      # ========================================
      # HEALTH CHECK
      # GET /api/health
      # ========================================
      get '/api/health' do
        { status: 'ok', system: 'finsystem', version: Config::VERSION, timestamp: Time.now.iso8601 }.to_json
      end
    end
  end
end
