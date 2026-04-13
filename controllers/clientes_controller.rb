# frozen_string_literal: true
# controllers/clientes_controller.rb - CRUD completo de clientes

module FinSystem
  module Controllers
    class ClientesController < Sinatra::Base
      helpers Middleware::Auth::AuthHelpers
      helpers Helpers::ViewHelpers

      set :views, File.join(File.dirname(__FILE__), '..', 'views')
      set :raise_errors, true

      before { autenticar_requisicao }

      # Listar clientes
      get '/clientes' do
        requer_nivel('operador')
        @empresa_id = params[:empresa_id]
        @busca = params[:busca]
        @page = (params[:page] || 1).to_i
        @per_page = 20

        @empresas = Models::Empresa.todas

        query = FinSystem::Database.db[:clientes]
                  .left_join(:empresas, Sequel[:empresas][:id] => Sequel[:clientes][:empresa_id])
                  .select_all(:clientes)
                  .select_append(Sequel[:empresas][:nome_fantasia].as(:empresa_nome))

        query = query.where(Sequel[:clientes][:empresa_id] => @empresa_id.to_i) if @empresa_id && !@empresa_id.empty?
        query = query.where(Sequel.like(Sequel[:clientes][:nome], "%#{@busca}%") | Sequel.like(Sequel[:clientes][:cnpj_cpf_ein], "%#{@busca}%")) if @busca && !@busca.empty?

        @total = query.count
        @total_pages = (@total / @per_page.to_f).ceil
        @clientes = query.order(Sequel[:clientes][:nome]).limit(@per_page).offset((@page - 1) * @per_page).all

        erb :'clientes/index', layout: :'layouts/application'
      end

      # Novo cliente
      get '/clientes/novo' do
        requer_nivel('operador')
        @empresas = Models::Empresa.todas
        @cliente = {}
        erb :'clientes/form', layout: :'layouts/application'
      end

      # Criar cliente
      post '/clientes' do
        requer_nivel('operador')

        errors = Services::Validation.validate_cliente(params)
        unless errors.empty?
          session[:flash_error] = errors.join(', ')
          redirect '/clientes/novo'
          return
        end

        FinSystem::Database.db[:clientes].insert(
          empresa_id: params[:empresa_id]&.to_i,
          nome: params[:nome].strip,
          cnpj_cpf_ein: params[:cnpj_cpf_ein]&.strip,
          razao_social: params[:razao_social]&.strip,
          nome_fantasia: params[:nome_fantasia]&.strip,
          tipo: params[:tipo] || 'PJ',
          email: params[:email]&.strip,
          telefone: params[:telefone]&.strip,
          endereco: params[:endereco]&.strip,
          cidade: params[:cidade]&.strip,
          estado: params[:estado]&.strip,
          pais: params[:pais] || 'BR'
        )

        Models::AuditLog.registrar(
          usuario_id: usuario_logado[:id],
          acao: 'create',
          entidade: 'cliente',
          detalhes: "Cliente criado: #{params[:nome]}",
          ip: request.ip
        )

        session[:flash_message] = "Cliente #{params[:nome]} cadastrado!"
        redirect '/clientes'
      end

      # Editar cliente
      get '/clientes/:id/editar' do
        requer_nivel('operador')
        @cliente = FinSystem::Database.db[:clientes].where(id: params[:id].to_i).first
        halt 404 unless @cliente
        @empresas = Models::Empresa.todas
        erb :'clientes/form', layout: :'layouts/application'
      end

      # Atualizar cliente
      put '/clientes/:id' do
        requer_nivel('operador')

        errors = Services::Validation.validate_cliente(params)
        unless errors.empty?
          session[:flash_error] = errors.join(', ')
          redirect "/clientes/#{params[:id]}/editar"
          return
        end

        FinSystem::Database.db[:clientes].where(id: params[:id].to_i).update(
          empresa_id: params[:empresa_id]&.to_i,
          nome: params[:nome].strip,
          cnpj_cpf_ein: params[:cnpj_cpf_ein]&.strip,
          razao_social: params[:razao_social]&.strip,
          nome_fantasia: params[:nome_fantasia]&.strip,
          tipo: params[:tipo] || 'PJ',
          email: params[:email]&.strip,
          telefone: params[:telefone]&.strip,
          endereco: params[:endereco]&.strip,
          cidade: params[:cidade]&.strip,
          estado: params[:estado]&.strip,
          pais: params[:pais] || 'BR'
        )

        Models::AuditLog.registrar(
          usuario_id: usuario_logado[:id],
          acao: 'update',
          entidade: 'cliente',
          entidade_id: params[:id].to_i,
          detalhes: "Cliente atualizado: #{params[:nome]}",
          ip: request.ip
        )

        session[:flash_message] = 'Cliente atualizado!'
        redirect '/clientes'
      end

      # Desativar cliente
      delete '/clientes/:id' do
        requer_nivel('gerente')
        FinSystem::Database.db[:clientes].where(id: params[:id].to_i).update(ativo: false)

        Models::AuditLog.registrar(
          usuario_id: usuario_logado[:id],
          acao: 'delete',
          entidade: 'cliente',
          entidade_id: params[:id].to_i,
          ip: request.ip
        )

        session[:flash_message] = 'Cliente desativado!'
        redirect '/clientes'
      end

      # ========================================
      # API JSON - Busca por CNPJ/CPF
      # ========================================
      get '/api/clientes/buscar_documento' do
        content_type :json
        doc = params[:documento]&.gsub(/\D/, '')
        return { success: false, message: 'Documento não informado' }.to_json if doc.nil? || doc.empty?

        cliente = FinSystem::Database.db[:clientes].where(ativo: true).where(
          Sequel.lit("REPLACE(REPLACE(REPLACE(REPLACE(cnpj_cpf_ein, '.', ''), '-', ''), '/', ''), ' ', '') = ?", doc)
        ).first

        if cliente
          { success: true, encontrado: true, data: {
            id: cliente[:id], nome: cliente[:nome],
            razao_social: cliente[:razao_social], nome_fantasia: cliente[:nome_fantasia],
            cnpj_cpf_ein: cliente[:cnpj_cpf_ein], email: cliente[:email],
            telefone: cliente[:telefone], endereco: cliente[:endereco],
            cidade: cliente[:cidade], estado: cliente[:estado]
          }}.to_json
        else
          { success: true, encontrado: false }.to_json
        end
      end

      # Criar cliente inline via JSON (da tela de movimentação)
      post '/api/clientes/criar_rapido' do
        content_type :json
        begin
          dados = JSON.parse(request.body.read, symbolize_names: true)
          
          # Verificar se já existe
          doc_limpo = dados[:cnpj_cpf_ein]&.gsub(/\D/, '')
          existente = FinSystem::Database.db[:clientes].where(ativo: true).where(
            Sequel.lit("REPLACE(REPLACE(REPLACE(REPLACE(cnpj_cpf_ein, '.', ''), '-', ''), '/', ''), ' ', '') = ?", doc_limpo)
          ).first
          
          if existente
            return { success: true, data: { id: existente[:id], nome: existente[:nome] } }.to_json
          end

          nome = dados[:razao_social] || dados[:nome_fantasia] || dados[:nome] || ''
          id = FinSystem::Database.db[:clientes].insert(
            nome: nome.strip,
            razao_social: dados[:razao_social]&.strip,
            nome_fantasia: dados[:nome_fantasia]&.strip,
            cnpj_cpf_ein: dados[:cnpj_cpf_ein]&.strip,
            tipo: doc_limpo.to_s.length > 11 ? 'PJ' : 'PF',
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
