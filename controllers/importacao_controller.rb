# frozen_string_literal: true
# controllers/importacao_controller.rb - Importação de extratos bancários

require 'json'
require 'tmpdir'
require 'fileutils'

module FinSystem
  module Controllers
    class ImportacaoController < Sinatra::Base
      helpers Middleware::Auth::AuthHelpers
      helpers Helpers::ViewHelpers

      set :views, File.join(File.dirname(__FILE__), '..', 'views')

      before { autenticar_requisicao }

      # ========================================
      # FORMULÁRIO DE UPLOAD
      # ========================================
      get '/importacao' do
        @empresas = Models::Empresa.todas
        @contas   = Models::Empresa.todas_contas
        @categorias = db[:categorias].order(:nome).all rescue []

        erb :'importacao/index', layout: :'layouts/application'
      end

      # ========================================
      # PROCESSAR ARQUIVO → PREVIEW
      # ========================================
      post '/importacao/processar' do
        arquivo    = params[:arquivo]
        conta_id   = params[:conta_bancaria_id]
        empresa_id = params[:empresa_id]

        unless arquivo && arquivo[:filename] && conta_id.to_i > 0 && empresa_id.to_i > 0
          session[:flash_error] = 'Selecione empresa, conta e arquivo.'
          redirect '/importacao'
        end

        begin
          # Salvar em temp para processar
          tmp_path = File.join(Dir.tmpdir, "extrato_#{SecureRandom.hex(8)}_#{arquivo[:filename]}")
          FileUtils.cp(arquivo[:tempfile].path, tmp_path)

          transacoes = Services::ExtratoParser.parse(tmp_path, arquivo[:filename])
          FileUtils.rm_f(tmp_path)

          if transacoes.empty?
            session[:flash_error] = 'Nenhuma transação encontrada no arquivo. Verifique o formato.'
            redirect '/importacao'
          end

          # Detectar duplicatas: mesmo dia + valor + conta
          conta_movs = db[:movimentacoes]
                         .where(conta_bancaria_id: conta_id.to_i)
                         .select(:data_movimentacao, :valor_bruto, :tipo)
                         .all

          transacoes_com_status = transacoes.map.with_index do |t, i|
            duplicata = conta_movs.any? do |m|
              m[:data_movimentacao].to_s == t[:data].to_s &&
              m[:valor_bruto].to_f.round(2) == t[:valor].to_f.round(2) &&
              m[:tipo] == t[:tipo]
            end
            t.merge(idx: i, duplicata: duplicata, importar: !duplicata)
          end

          # Salvar em arquivo temp para o passo de confirmação
          token = SecureRandom.hex(16)
          cache_path = File.join(Dir.tmpdir, "extrato_preview_#{token}.json")
          File.write(cache_path, {
            conta_bancaria_id: conta_id.to_i,
            empresa_id: empresa_id.to_i,
            transacoes: transacoes_com_status.map { |t| t.transform_keys(&:to_s).merge('data' => t[:data].to_s) }
          }.to_json)

          session[:importacao_token] = token
          session[:importacao_arquivo] = arquivo[:filename]

          @arquivo_nome  = arquivo[:filename]
          @conta_id      = conta_id.to_i
          @empresa_id    = empresa_id.to_i
          @transacoes    = transacoes_com_status
          @token         = token
          @empresas      = Models::Empresa.todas
          @contas        = Models::Empresa.todas_contas
          @categorias    = db[:categorias].order(:nome).all rescue []
          @conta_info    = @contas.find { |c| c[:id] == @conta_id }

          erb :'importacao/preview', layout: :'layouts/application'

        rescue => e
          FileUtils.rm_f(tmp_path) if tmp_path && File.exist?(tmp_path.to_s)
          session[:flash_error] = "Erro ao processar arquivo: #{e.message}"
          redirect '/importacao'
        end
      end

      # ========================================
      # CONFIRMAR IMPORTAÇÃO
      # ========================================
      post '/importacao/confirmar' do
        token = params[:token] || session[:importacao_token]
        cache_path = File.join(Dir.tmpdir, "extrato_preview_#{token}.json")

        unless token && File.exist?(cache_path)
          session[:flash_error] = 'Sessão expirada. Faça o upload novamente.'
          redirect '/importacao'
        end

        dados = JSON.parse(File.read(cache_path))
        conta_id   = dados['conta_bancaria_id'].to_i
        empresa_id = dados['empresa_id'].to_i
        transacoes = dados['transacoes']

        # Índices selecionados pelo usuário (checkboxes)
        selecionados = (params[:importar] || []).map(&:to_i)

        categoria_global = params[:categoria_id].to_s.strip.empty? ? nil : params[:categoria_id].to_i
        status_import    = params[:status_import] || 'confirmado'

        # Categoria por linha (hash idx → cat_id)
        cat_por_linha = {}
        (params[:categoria_linha] || {}).each { |idx, v| cat_por_linha[idx.to_i] = v.to_i unless v.to_s.strip.empty? }

        importadas = 0
        erros = []

        db_conn = Database.db
        db_conn.transaction do
          transacoes.each do |t|
            idx = t['idx'].to_i
            next unless selecionados.include?(idx)

            cat_id = cat_por_linha[idx] || categoria_global

            begin
              Models::Movimentacao.criar(
                empresa_id:        empresa_id,
                conta_bancaria_id: conta_id,
                categoria_id:      cat_id,
                usuario_id:        usuario_logado[:id],
                tipo:              t['tipo'],
                data_movimentacao: t['data'],
                data_competencia:  t['data'],
                descricao:         t['descricao'],
                valor_bruto:       ('%.2f' % t['valor'].to_f).gsub('.', ','),
                valor_liquido:     ('%.2f' % t['valor'].to_f).gsub('.', ','),
                lucro:             '0',
                tipo_cobranca:     'unica',
                status:            status_import,
                forma_pagamento:   'outros',
                referencia_banco:  t['referencia'],
                observacoes:       'Importado via extrato bancário'
              )
              importadas += 1
            rescue => e
              erros << "Linha #{idx + 1}: #{e.message}"
            end
          end
        end

        FileUtils.rm_f(cache_path)
        session.delete(:importacao_token)
        session.delete(:importacao_arquivo)

        Models::AuditLog.registrar(
          usuario_id: usuario_logado[:id],
          acao: 'create',
          entidade: 'importacao_extrato',
          detalhes: "Importadas #{importadas} movimentações da conta #{conta_id}",
          ip: request.ip
        ) if importadas > 0

        if erros.any?
          session[:flash_message] = "#{importadas} movimentação(ões) importada(s). #{erros.size} erro(s): #{erros.first(3).join('; ')}"
        else
          session[:flash_message] = "#{importadas} movimentação(ões) importada(s) com sucesso!"
        end

        redirect '/movimentacoes'
      end

      # ========================================
      # LIMPEZA — EXCLUIR IMPORTAÇÕES COM ERRO
      # ========================================
      get '/importacao/limpar-erros' do
        @movs = db[:movimentacoes]
                  .where(observacoes: 'Importado via extrato bancário')
                  .left_join(:contas_bancarias, Sequel[:contas_bancarias][:id] => Sequel[:movimentacoes][:conta_bancaria_id])
                  .left_join(:empresas, Sequel[:empresas][:id] => Sequel[:movimentacoes][:empresa_id])
                  .select_all(:movimentacoes)
                  .select_append(Sequel[:contas_bancarias][:banco].as(:banco_nome))
                  .select_append(Sequel[:contas_bancarias][:apelido].as(:conta_apelido))
                  .select_append(Sequel[:empresas][:nome_fantasia].as(:empresa_nome))
                  .order(Sequel.desc(Sequel[:movimentacoes][:data_movimentacao]))
                  .all

        erb :'importacao/limpar_erros', layout: :'layouts/application'
      end

      post '/importacao/limpar-erros/confirmar' do
        ids = db[:movimentacoes]
                .where(observacoes: 'Importado via extrato bancário')
                .select_map(:id)

        contas_afetadas = db[:movimentacoes]
                            .where(id: ids)
                            .select_map(:conta_bancaria_id)
                            .uniq

        db[:movimentacoes].where(id: ids).delete

        contas_afetadas.each do |conta_id|
          Models::Movimentacao.atualizar_saldo_conta(conta_id)
        end

        Models::AuditLog.registrar(
          usuario_id: usuario_logado[:id],
          acao: 'delete',
          entidade: 'importacao_extrato',
          detalhes: "Excluídas #{ids.size} movimentações importadas com erro de valor",
          ip: request.ip
        )

        session[:flash_message] = "#{ids.size} movimentação(ões) excluída(s). Saldos recalculados. Reimporte os extratos."
        redirect '/importacao'
      end

      private

      def db
        Database.db
      end
    end
  end
end
