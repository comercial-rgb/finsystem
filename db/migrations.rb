# frozen_string_literal: true
# db/migrations.rb - Criação de todas as tabelas do sistema

module FinSystem
  module Migrations
    def self.run(db)
      # ========================================
      # USUÁRIOS E AUTENTICAÇÃO
      # ========================================
      db.create_table?(:usuarios) do
        primary_key :id
        String :nome, null: false
        String :email, null: false, unique: true
        String :senha_hash, null: false
        String :nivel_acesso, null: false, default: 'operador'
        # Níveis: admin, gerente, financeiro, operador, pessoal
        TrueClass :ativo, default: true
        DateTime :ultimo_login
        DateTime :created_at, default: Sequel::CURRENT_TIMESTAMP
        DateTime :updated_at, default: Sequel::CURRENT_TIMESTAMP
      end

      # ========================================
      # EMPRESAS DO GRUPO
      # ========================================
      db.create_table?(:empresas) do
        primary_key :id
        String :razao_social, null: false
        String :nome_fantasia, null: false
        String :cnpj_ein, null: false, unique: true  # CNPJ (BR) ou EIN (US)
        String :pais, null: false, default: 'BR'     # BR ou US
        String :estado
        String :cidade
        String :endereco
        String :regime_tributario  # Simples Nacional, Lucro Presumido, LLC, etc.
        TrueClass :ativo, default: true
        DateTime :created_at, default: Sequel::CURRENT_TIMESTAMP
        DateTime :updated_at, default: Sequel::CURRENT_TIMESTAMP
      end

      # ========================================
      # SÓCIOS E PARTICIPAÇÃO
      # ========================================
      db.create_table?(:socios) do
        primary_key :id
        foreign_key :empresa_id, :empresas, null: false
        String :nome, null: false
        String :cpf_ssn                              # CPF (BR) ou SSN (US)
        BigDecimal :percentual_participacao, size: [5, 2], null: false  # Ex: 60.00
        String :tipo, default: 'socio'               # socio, administrador, investidor
        TrueClass :ativo, default: true
        DateTime :created_at, default: Sequel::CURRENT_TIMESTAMP
      end

      # ========================================
      # CONTAS BANCÁRIAS
      # ========================================
      db.create_table?(:contas_bancarias) do
        primary_key :id
        foreign_key :empresa_id, :empresas
        String :banco, null: false                   # Itaú, Sicredi, Banco do Brasil, etc.
        String :agencia
        String :conta
        String :tipo_conta, default: 'corrente'      # corrente, poupança, checking, savings
        String :moeda, default: 'BRL'                # BRL ou USD
        BigDecimal :saldo_inicial, size: [15, 2], default: 0
        String :apelido                              # Nome amigável: "Itaú Principal"
        TrueClass :ativo, default: true
        DateTime :created_at, default: Sequel::CURRENT_TIMESTAMP
      end

      # ========================================
      # CLIENTES
      # ========================================
      db.create_table?(:clientes) do
        primary_key :id
        foreign_key :empresa_id, :empresas
        String :nome, null: false
        String :cnpj_cpf_ein                         # Documento do cliente
        String :tipo, default: 'PJ'                  # PJ ou PF
        String :email
        String :telefone
        String :cidade
        String :estado
        String :pais, default: 'BR'
        TrueClass :ativo, default: true
        DateTime :created_at, default: Sequel::CURRENT_TIMESTAMP
      end

      # ========================================
      # FORNECEDORES DA REDE CREDENCIADA
      # ========================================
      db.create_table?(:fornecedores) do
        primary_key :id
        foreign_key :empresa_id, :empresas
        String :nome, null: false
        String :cnpj_cpf_ein
        String :tipo, default: 'rede_credenciada'    # rede_credenciada, servico, produto
        String :categoria                            # posto, oficina, loja, etc.
        String :email
        String :telefone
        String :cidade
        String :estado
        String :pais, default: 'BR'
        String :dados_bancarios_json, text: true     # JSON com dados para repasse
        TrueClass :ativo, default: true
        DateTime :created_at, default: Sequel::CURRENT_TIMESTAMP
      end

      # ========================================
      # CATEGORIAS DE MOVIMENTAÇÃO
      # ========================================
      db.create_table?(:categorias) do
        primary_key :id
        String :nome, null: false
        String :tipo, null: false                    # receita, despesa
        String :subtipo                              # boleto, repasse, antecipacao, salario, aluguel, servidor, ia, utilidade
        String :descricao
        String :cor, default: '#6366f1'              # Cor para visualização
        TrueClass :ativo, default: true
        DateTime :created_at, default: Sequel::CURRENT_TIMESTAMP
      end

      # ========================================
      # MOVIMENTAÇÕES FINANCEIRAS (Core)
      # ========================================
      db.create_table?(:movimentacoes) do
        primary_key :id
        foreign_key :empresa_id, :empresas, null: false
        foreign_key :conta_bancaria_id, :contas_bancarias, null: false
        foreign_key :categoria_id, :categorias
        foreign_key :cliente_id, :clientes
        foreign_key :fornecedor_id, :fornecedores
        foreign_key :usuario_id, :usuarios, null: false  # Quem lançou

        String :tipo, null: false                    # receita, despesa
        Date :data_movimentacao, null: false
        Date :data_competencia                       # Mês de competência
        String :descricao, null: false
        BigDecimal :valor_bruto, size: [15, 2], null: false
        BigDecimal :valor_liquido, size: [15, 2]     # Valor após deduções
        BigDecimal :lucro, size: [15, 2], default: 0 # Lucro da operação

        # Campos específicos para tipos de operação
        String :tipo_operacao                        # faturamento, antecipacao, boleto, repasse, taxa
        String :numero_documento                     # Nº do boleto, NF, etc.
        String :status, default: 'confirmado'        # pendente, confirmado, cancelado, conciliado
        String :forma_pagamento                      # pix, ted, boleto, cartao, dinheiro
        String :observacoes, text: true

        # Antecipação a fornecedores
        TrueClass :is_antecipacao, default: false
        BigDecimal :valor_antecipado, size: [15, 2]  # Valor enviado ao fornecedor
        BigDecimal :taxa_antecipacao, size: [15, 2]  # Lucro da antecipação
        BigDecimal :valor_original_faturamento, size: [15, 2]  # Valor que seria recebido

        # Recorrência e parcelamento
        String :tipo_cobranca, default: 'unica'      # unica, recorrente, parcelada
        Integer :total_parcelas, default: 1
        Integer :parcela_atual, default: 1
        Integer :dia_vencimento_recorrente             # Dia do mês para lembrete
        Date :data_proximo_vencimento                  # Próxima data de pagamento
        TrueClass :pago, default: false                # Se já foi pago neste ciclo
        Integer :recorrencia_pai_id                     # ID da movimentação original (para parcelas/recorrências)

        # Conciliação bancária
        TrueClass :conciliado, default: false
        Date :data_conciliacao
        String :referencia_banco                     # ID/referência do extrato bancário

        DateTime :created_at, default: Sequel::CURRENT_TIMESTAMP
        DateTime :updated_at, default: Sequel::CURRENT_TIMESTAMP
      end

      # Adicionar colunas novas se tabela já existir
      unless db[:movimentacoes].columns.include?(:tipo_cobranca)
        db.alter_table(:movimentacoes) do
          add_column :tipo_cobranca, String, default: 'unica'
          add_column :total_parcelas, Integer, default: 1
          add_column :parcela_atual, Integer, default: 1
          add_column :dia_vencimento_recorrente, Integer
          add_column :data_proximo_vencimento, Date
          add_column :pago, :boolean, default: false
          add_column :recorrencia_pai_id, Integer
        end
      end

      # ========================================
      # COMPROVANTES / ANEXOS
      # ========================================
      db.create_table?(:comprovantes) do
        primary_key :id
        foreign_key :movimentacao_id, :movimentacoes, null: false
        foreign_key :usuario_id, :usuarios, null: false
        String :nome_arquivo, null: false
        String :nome_original, null: false
        String :tipo_arquivo                         # pdf, jpg, png, etc.
        Integer :tamanho_bytes
        String :caminho_arquivo, null: false          # Path no servidor
        String :hash_arquivo                          # SHA256 para integridade
        DateTime :created_at, default: Sequel::CURRENT_TIMESTAMP
      end

      # ========================================
      # FINANÇAS PESSOAIS (Módulo Winner)
      # ========================================
      db.create_table?(:pessoal_categorias) do
        primary_key :id
        foreign_key :usuario_id, :usuarios, null: false
        String :nome, null: false
        String :tipo, null: false                    # receita, despesa, investimento
        String :cor, default: '#10b981'
        DateTime :created_at, default: Sequel::CURRENT_TIMESTAMP
      end

      db.create_table?(:pessoal_movimentacoes) do
        primary_key :id
        foreign_key :usuario_id, :usuarios, null: false
        foreign_key :categoria_id, :pessoal_categorias
        String :tipo, null: false                    # receita, despesa, investimento
        Date :data_movimentacao, null: false
        String :descricao, null: false
        BigDecimal :valor, size: [15, 2], null: false
        String :forma_pagamento
        String :observacoes, text: true
        TrueClass :recorrente, default: false
        String :frequencia_recorrencia               # mensal, semanal, anual
        DateTime :created_at, default: Sequel::CURRENT_TIMESTAMP
      end

      db.create_table?(:pessoal_comprovantes) do
        primary_key :id
        foreign_key :movimentacao_id, :pessoal_movimentacoes, null: false
        String :nome_arquivo, null: false
        String :nome_original, null: false
        String :caminho_arquivo, null: false
        String :hash_arquivo
        DateTime :created_at, default: Sequel::CURRENT_TIMESTAMP
      end

      # ========================================
      # CONTAS BANCÁRIAS PESSOAIS
      # ========================================
      db.create_table?(:pessoal_contas_bancarias) do
        primary_key :id
        foreign_key :usuario_id, :usuarios, null: false
        String :banco, null: false
        String :agencia
        String :conta
        String :tipo_conta, default: 'corrente'      # corrente, poupança, checking, savings
        String :moeda, default: 'BRL'
        BigDecimal :saldo_inicial, size: [15, 2], default: 0
        String :apelido                              # Nome amigável
        TrueClass :ativo, default: true
        DateTime :created_at, default: Sequel::CURRENT_TIMESTAMP
      end

      # ========================================
      # LOG DE AUDITORIA
      # ========================================
      db.create_table?(:audit_logs) do
        primary_key :id
        foreign_key :usuario_id, :usuarios
        String :acao, null: false                    # create, update, delete, login, logout
        String :entidade                             # movimentacao, empresa, usuario, etc.
        Integer :entidade_id
        String :detalhes, text: true                 # JSON com before/after
        String :ip_address
        DateTime :created_at, default: Sequel::CURRENT_TIMESTAMP
      end

      # ========================================
      # SESSÕES
      # ========================================
      db.create_table?(:sessions) do
        primary_key :id
        foreign_key :usuario_id, :usuarios, null: false
        String :token, null: false, unique: true
        DateTime :expires_at, null: false
        String :ip_address
        String :user_agent, text: true
        DateTime :created_at, default: Sequel::CURRENT_TIMESTAMP
      end

      # ========================================
      # TOKENS DE RECUPERAÇÃO DE SENHA
      # ========================================
      db.create_table?(:password_reset_tokens) do
        primary_key :id
        foreign_key :usuario_id, :usuarios, null: false
        String :token, null: false, unique: true
        DateTime :expires_at, null: false
        TrueClass :used, default: false
        DateTime :created_at, default: Sequel::CURRENT_TIMESTAMP
      end

      # ========================================
      # CARTÕES DE CRÉDITO (EMPRESARIAL)
      # ========================================
      db.create_table?(:cartoes_credito) do
        primary_key :id
        foreign_key :empresa_id, :empresas, null: false
        String :bandeira, null: false                # Visa, Mastercard, Elo, Amex
        String :banco, null: false                   # Banco emissor
        String :ultimos_digitos                      # Últimos 4 dígitos
        String :apelido                              # Nome amigável
        String :titular                              # Nome no cartão
        BigDecimal :limite_total, size: [15, 2], default: 0
        BigDecimal :limite_disponivel, size: [15, 2], default: 0
        Integer :dia_fechamento, default: 1          # Dia de fechamento da fatura
        Integer :dia_vencimento, default: 10         # Dia de vencimento
        String :moeda, default: 'BRL'
        TrueClass :ativo, default: true
        DateTime :created_at, default: Sequel::CURRENT_TIMESTAMP
        DateTime :updated_at, default: Sequel::CURRENT_TIMESTAMP
      end

      # ========================================
      # FATURAS DE CARTÃO (EMPRESARIAL)
      # ========================================
      db.create_table?(:faturas_cartao) do
        primary_key :id
        foreign_key :cartao_id, :cartoes_credito, null: false
        Integer :mes_referencia, null: false
        Integer :ano_referencia, null: false
        Date :data_fechamento
        Date :data_vencimento
        BigDecimal :valor_total, size: [15, 2], default: 0
        BigDecimal :valor_pago, size: [15, 2], default: 0
        String :status, default: 'aberta'            # aberta, fechada, paga, parcial
        DateTime :created_at, default: Sequel::CURRENT_TIMESTAMP
      end

      # ========================================
      # DESPESAS NO CARTÃO (EMPRESARIAL)
      # ========================================
      db.create_table?(:despesas_cartao) do
        primary_key :id
        foreign_key :cartao_id, :cartoes_credito, null: false
        foreign_key :fatura_id, :faturas_cartao
        foreign_key :categoria_id, :categorias
        foreign_key :empresa_id, :empresas, null: false
        foreign_key :usuario_id, :usuarios, null: false
        Date :data_compra, null: false
        String :descricao, null: false
        BigDecimal :valor_total, size: [15, 2], null: false
        BigDecimal :valor_parcela, size: [15, 2], null: false
        Integer :parcela_atual, default: 1
        Integer :total_parcelas, default: 1
        String :status, default: 'pendente'          # pendente, paga, cancelada
        String :observacoes, text: true
        DateTime :created_at, default: Sequel::CURRENT_TIMESTAMP
      end

      # ========================================
      # CARTÕES DE CRÉDITO (PESSOAL)
      # ========================================
      db.create_table?(:pessoal_cartoes) do
        primary_key :id
        foreign_key :usuario_id, :usuarios, null: false
        String :bandeira, null: false
        String :banco, null: false
        String :ultimos_digitos
        String :apelido
        BigDecimal :limite_total, size: [15, 2], default: 0
        Integer :dia_fechamento, default: 1
        Integer :dia_vencimento, default: 10
        TrueClass :ativo, default: true
        DateTime :created_at, default: Sequel::CURRENT_TIMESTAMP
      end

      # ========================================
      # FATURAS DE CARTÃO (PESSOAL)
      # ========================================
      db.create_table?(:pessoal_faturas) do
        primary_key :id
        foreign_key :cartao_id, :pessoal_cartoes, null: false
        Integer :mes_referencia, null: false
        Integer :ano_referencia, null: false
        Date :data_fechamento
        Date :data_vencimento
        BigDecimal :valor_total, size: [15, 2], default: 0
        BigDecimal :valor_pago, size: [15, 2], default: 0
        String :status, default: 'aberta'
        DateTime :created_at, default: Sequel::CURRENT_TIMESTAMP
      end

      # ========================================
      # DESPESAS NO CARTÃO (PESSOAL)
      # ========================================
      db.create_table?(:pessoal_despesas_cartao) do
        primary_key :id
        foreign_key :cartao_id, :pessoal_cartoes, null: false
        foreign_key :fatura_id, :pessoal_faturas
        foreign_key :categoria_id, :pessoal_categorias
        foreign_key :usuario_id, :usuarios, null: false
        Date :data_compra, null: false
        String :descricao, null: false
        BigDecimal :valor_total, size: [15, 2], null: false
        BigDecimal :valor_parcela, size: [15, 2], null: false
        Integer :parcela_atual, default: 1
        Integer :total_parcelas, default: 1
        String :status, default: 'pendente'
        String :observacoes, text: true
        DateTime :created_at, default: Sequel::CURRENT_TIMESTAMP
      end

      # ========================================
      # TRANSFERÊNCIAS ENTRE CONTAS
      # ========================================
      db.create_table?(:transferencias) do
        primary_key :id
        foreign_key :conta_origem_id, :contas_bancarias, null: false
        foreign_key :conta_destino_id, :contas_bancarias, null: false
        foreign_key :usuario_id, :usuarios, null: false
        BigDecimal :valor, size: [15, 2], null: false
        Date :data_transferencia, null: false
        String :descricao
        String :observacoes, text: true
        Integer :movimentacao_saida_id
        Integer :movimentacao_entrada_id
        DateTime :created_at, default: Sequel::CURRENT_TIMESTAMP
      end

      # ========================================
      # SALDO ATUAL NAS CONTAS BANCÁRIAS
      # ========================================
      unless db[:contas_bancarias].columns.include?(:saldo_atual)
        db.alter_table(:contas_bancarias) do
          add_column :saldo_atual, BigDecimal, size: [15, 2], default: 0
        end
        # Inicializar saldo_atual = saldo_inicial para contas existentes
        db[:contas_bancarias].update(saldo_atual: Sequel[:saldo_inicial])
      end

      # ========================================
      # HISTÓRICO DE SALDOS (para relatórios)
      # ========================================
      db.create_table?(:historico_saldos) do
        primary_key :id
        foreign_key :conta_bancaria_id, :contas_bancarias, null: false
        Date :data_referencia, null: false
        BigDecimal :saldo, size: [15, 2], null: false
        String :tipo_evento                          # movimentacao, transferencia, ajuste
        Integer :evento_id                           # ID da movimentação ou transferência
        String :descricao
        DateTime :created_at, default: Sequel::CURRENT_TIMESTAMP
      end
    end
  end
end
