# frozen_string_literal: true
# controllers/fornecedores_controller.rb - CRUD completo de fornecedores

module FinSystem
  module Controllers
    class FornecedoresController < Sinatra::Base
      helpers Middleware::Auth::AuthHelpers
      helpers Helpers::ViewHelpers

      set :views, File.join(File.dirname(__FILE__), '..', 'views')
      set :raise_errors, true

      before { autenticar_requisicao }

      # Listar fornecedores
      get '/fornecedores' do
        requer_nivel('operador')
        @empresa_id = params[:empresa_id]
        @busca = params[:busca]
        @page = (params[:page] || 1).to_i
        @per_page = 20

        @empresas = Models::Empresa.todas

        query = FinSystem::Database.db[:fornecedores]
                  .left_join(:empresas, Sequel[:empresas][:id] => Sequel[:fornecedores][:empresa_id])
                  .select_all(:fornecedores)
                  .select_append(Sequel[:empresas][:nome_fantasia].as(:empresa_nome))

        query = query.where(Sequel[:fornecedores][:empresa_id] => @empresa_id.to_i) if @empresa_id && !@empresa_id.empty?
        query = query.where(Sequel.like(Sequel[:fornecedores][:nome], "%#{@busca}%") | Sequel.like(Sequel[:fornecedores][:cnpj_cpf_ein], "%#{@busca}%")) if @busca && !@busca.empty?

        @total = query.count
        @total_pages = (@total / @per_page.to_f).ceil
        @fornecedores = query.order(Sequel[:fornecedores][:nome]).limit(@per_page).offset((@page - 1) * @per_page).all

        erb :'fornecedores/index', layout: :'layouts/application'
      end

      # Novo fornecedor
      get '/fornecedores/novo' do
        requer_nivel('operador')
        @empresas = Models::Empresa.todas
        @fornecedor = {}
        erb :'fornecedores/form', layout: :'layouts/application'
      end

      # Criar fornecedor
      post '/fornecedores/criar' do
        requer_nivel('operador')

        errors = Services::Validation.validate_fornecedor(params)
        unless errors.empty?
          session[:flash_error] = errors.join(', ')
          redirect '/fornecedores/novo'
          return
        end

        FinSystem::Database.db[:fornecedores].insert(
          empresa_id: params[:empresa_id]&.to_i,
          nome: params[:nome].strip,
          cnpj_cpf_ein: params[:cnpj_cpf_ein]&.strip,
          razao_social: params[:razao_social]&.strip,
          nome_fantasia: params[:nome_fantasia]&.strip,
          tipo: params[:tipo_fornecedor] || 'rede_credenciada',
          categoria: params[:categoria]&.strip,
          email: params[:email]&.strip,
          telefone: params[:telefone]&.strip,
          endereco: params[:endereco]&.strip,
          cidade: params[:cidade]&.strip,
          estado: params[:estado]&.strip,
          pais: params[:pais] || 'BR',
          dados_bancarios_json: {
            banco: params[:banco],
            agencia: params[:agencia],
            conta: params[:conta_bancaria],
            pix: params[:pix]
          }.to_json
        )

        Models::AuditLog.registrar(
          usuario_id: usuario_logado[:id],
          acao: 'create',
          entidade: 'fornecedor',
          detalhes: "Fornecedor criado: #{params[:nome]}",
          ip: request.ip
        )

        session[:flash_message] = "Fornecedor #{params[:nome]} cadastrado!"
        redirect '/fornecedores'
      end

      # Editar fornecedor
      get '/fornecedores/:id/editar' do
        requer_nivel('operador')
        @fornecedor = FinSystem::Database.db[:fornecedores].where(id: params[:id].to_i).first
        halt 404 unless @fornecedor
        @empresas = Models::Empresa.todas
        erb :'fornecedores/form', layout: :'layouts/application'
      end

      # Atualizar fornecedor
      put '/fornecedores/:id' do
        requer_nivel('operador')

        errors = Services::Validation.validate_fornecedor(params)
        unless errors.empty?
          session[:flash_error] = errors.join(', ')
          redirect "/fornecedores/#{params[:id]}/editar"
          return
        end

        FinSystem::Database.db[:fornecedores].where(id: params[:id].to_i).update(
          empresa_id: params[:empresa_id]&.to_i,
          nome: params[:nome].strip,
          cnpj_cpf_ein: params[:cnpj_cpf_ein]&.strip,
          razao_social: params[:razao_social]&.strip,
          nome_fantasia: params[:nome_fantasia]&.strip,
          tipo: params[:tipo_fornecedor] || 'rede_credenciada',
          categoria: params[:categoria]&.strip,
          email: params[:email]&.strip,
          telefone: params[:telefone]&.strip,
          endereco: params[:endereco]&.strip,
          cidade: params[:cidade]&.strip,
          estado: params[:estado]&.strip,
          pais: params[:pais] || 'BR',
          dados_bancarios_json: {
            banco: params[:banco],
            agencia: params[:agencia],
            conta: params[:conta_bancaria],
            pix: params[:pix]
          }.to_json
        )

        Models::AuditLog.registrar(
          usuario_id: usuario_logado[:id],
          acao: 'update',
          entidade: 'fornecedor',
          entidade_id: params[:id].to_i,
          detalhes: "Fornecedor atualizado: #{params[:nome]}",
          ip: request.ip
        )

        session[:flash_message] = 'Fornecedor atualizado!'
        redirect '/fornecedores'
      end

      # Desativar fornecedor
      delete '/fornecedores/:id' do
        requer_nivel('gerente')
        FinSystem::Database.db[:fornecedores].where(id: params[:id].to_i).update(ativo: false)

        Models::AuditLog.registrar(
          usuario_id: usuario_logado[:id],
          acao: 'delete',
          entidade: 'fornecedor',
          entidade_id: params[:id].to_i,
          ip: request.ip
        )

        session[:flash_message] = 'Fornecedor desativado!'
        redirect '/fornecedores'
      end

      # ========================================
      # API JSON - Busca por CNPJ/CPF
      # ========================================
      get '/api/fornecedores/buscar_documento' do
        content_type :json
        halt 401, { error: 'Não autorizado' }.to_json unless session[:usuario_id]
        doc = params[:documento]&.gsub(/\D/, '')
        return { success: false, message: 'Documento não informado' }.to_json if doc.nil? || doc.empty?

        fornecedor = FinSystem::Database.db[:fornecedores].where(ativo: true).where(
          Sequel.lit("REPLACE(REPLACE(REPLACE(REPLACE(cnpj_cpf_ein, '.', ''), '-', ''), '/', ''), ' ', '') = ?", doc)
        ).first

        if fornecedor
          { success: true, encontrado: true, data: {
            id: fornecedor[:id], nome: fornecedor[:nome],
            razao_social: fornecedor[:razao_social], nome_fantasia: fornecedor[:nome_fantasia],
            cnpj_cpf_ein: fornecedor[:cnpj_cpf_ein], email: fornecedor[:email],
            telefone: fornecedor[:telefone], endereco: fornecedor[:endereco],
            cidade: fornecedor[:cidade], estado: fornecedor[:estado]
          }}.to_json
        else
          { success: true, encontrado: false }.to_json
        end
      end

      # Criar fornecedor inline via JSON
      post '/api/fornecedores/criar_rapido' do
        content_type :json
        halt 401, { error: 'Não autorizado' }.to_json unless session[:usuario_id]
        begin
          dados = JSON.parse(request.body.read, symbolize_names: true)

          doc_limpo = dados[:cnpj_cpf_ein]&.gsub(/\D/, '')
          existente = FinSystem::Database.db[:fornecedores].where(ativo: true).where(
            Sequel.lit("REPLACE(REPLACE(REPLACE(REPLACE(cnpj_cpf_ein, '.', ''), '-', ''), '/', ''), ' ', '') = ?", doc_limpo)
          ).first

          if existente
            return { success: true, data: { id: existente[:id], nome: existente[:nome] } }.to_json
          end

          nome = dados[:razao_social] || dados[:nome_fantasia] || dados[:nome] || ''
          id = FinSystem::Database.db[:fornecedores].insert(
            nome: nome.strip,
            razao_social: dados[:razao_social]&.strip,
            nome_fantasia: dados[:nome_fantasia]&.strip,
            cnpj_cpf_ein: dados[:cnpj_cpf_ein]&.strip,
            tipo: 'rede_credenciada',
            email: dados[:email]&.strip,
            telefone: dados[:telefone]&.strip,
            endereco: dados[:endereco]&.strip,
            cidade: dados[:cidade]&.strip,
            estado: dados[:estado]&.strip,
            pais: 'BR'
          )
          { success: true, data: { id: id, nome: nome.strip } }.to_json
        rescue => e
          status 422
          { success: false, message: e.message }.to_json
        end
      end
    end
  end
end
