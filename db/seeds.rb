# frozen_string_literal: true
# db/seeds.rb - Dados iniciais do sistema

require 'bcrypt'

module FinSystem
  module Seeds
    def self.run(db)
      puts "🌱 Inserindo dados iniciais..."

      # ========================================
      # USUÁRIO ADMIN GERAL
      # ========================================
      if db[:usuarios].where(email: 'admin@frotainstasolutions.com.br').empty?
        db[:usuarios].insert(
          nome: 'Administrador Geral',
          email: 'admin@frotainstasolutions.com.br',
          senha_hash: BCrypt::Password.create('FrotaInsta@2026!'),
          nivel_acesso: 'admin',
          ativo: true
        )
        puts "  ✅ Admin Geral criado (email: admin@frotainstasolutions.com.br / senha: FrotaInsta@2026!)"
      end

      # Manter compatibilidade com admin antigo
      if db[:usuarios].where(email: 'admin@instasolutions.com.br').empty?
        db[:usuarios].insert(
          nome: 'Winner',
          email: 'admin@instasolutions.com.br',
          senha_hash: BCrypt::Password.create('admin123'),
          nivel_acesso: 'admin',
          ativo: true
        )
        puts "  ✅ Usuário Winner criado (email: admin@instasolutions.com.br / senha: admin123)"
      end

      # ========================================
      # EMPRESAS DO GRUPO
      # ========================================
      empresas_data = [
        {
          razao_social: 'InstaSolutions Produtos e Gestão Empresarial LTDA',
          nome_fantasia: 'InstaSolutions',
          cnpj_ein: '00.000.000/0001-00',
          pais: 'BR', estado: 'SP', cidade: 'Barueri/Alphaville',
          regime_tributario: 'Simples Nacional'
        },
        {
          razao_social: 'MS Frotas Administradora de Benefícios LTDA',
          nome_fantasia: 'Engine Sistemas',
          cnpj_ein: '00.000.000/0002-00',
          pais: 'BR', estado: 'SP', cidade: 'Osasco',
          regime_tributario: 'Simples Nacional'
        },
        {
          razao_social: 'TechTrust AutoSolutions LLC',
          nome_fantasia: 'TechTrust AutoSolutions',
          cnpj_ein: '00-0000000',
          pais: 'US', estado: 'FL', cidade: 'Port St. Lucie',
          regime_tributario: 'LLC'
        },
        {
          razao_social: 'Empresa 4 - A Definir',
          nome_fantasia: 'Empresa 4',
          cnpj_ein: '00.000.000/0004-00',
          pais: 'BR', estado: 'SP', cidade: 'São Paulo',
          regime_tributario: 'Simples Nacional'
        }
      ]

      empresas_data.each do |emp|
        if db[:empresas].where(cnpj_ein: emp[:cnpj_ein]).empty?
          db[:empresas].insert(emp)
          puts "  ✅ Empresa: #{emp[:nome_fantasia]}"
        end
      end

      # ========================================
      # SÓCIOS (2 por empresa, porcentagens a definir)
      # ========================================
      empresas = db[:empresas].all
      empresas.each do |emp|
        if db[:socios].where(empresa_id: emp[:id]).empty?
          db[:socios].insert(empresa_id: emp[:id], nome: 'Sócio 1 - A Definir',
                            percentual_participacao: 50.0, tipo: 'administrador')
          db[:socios].insert(empresa_id: emp[:id], nome: 'Sócio 2 - A Definir',
                            percentual_participacao: 50.0, tipo: 'socio')
          puts "  ✅ Sócios cadastrados para: #{emp[:nome_fantasia]}"
        end
      end

      # ========================================
      # CONTAS BANCÁRIAS
      # ========================================
      bancos = [
        { banco: 'Itaú', apelido: 'Itaú Principal', moeda: 'BRL' },
        { banco: 'Sicredi', apelido: 'Sicredi', moeda: 'BRL' },
        { banco: 'Banco do Brasil', apelido: 'BB', moeda: 'BRL' }
      ]

      primeira_empresa = db[:empresas].first
      bancos.each do |b|
        if db[:contas_bancarias].where(banco: b[:banco], empresa_id: primeira_empresa[:id]).empty?
          db[:contas_bancarias].insert(b.merge(empresa_id: primeira_empresa[:id], saldo_inicial: 0))
          puts "  ✅ Conta: #{b[:apelido]}"
        end
      end

      # ========================================
      # CATEGORIAS DE RECEITA
      # ========================================
      categorias_receita = [
        { nome: 'Faturamento de Clientes', subtipo: 'faturamento', cor: '#10b981' },
        { nome: 'Taxa de Antecipação', subtipo: 'antecipacao', cor: '#06b6d4' },
        { nome: 'Comissão sobre Serviços', subtipo: 'comissao', cor: '#8b5cf6' },
        { nome: 'Serviços Automotivos (US)', subtipo: 'servico_auto', cor: '#f59e0b' },
        { nome: 'Licenciamento SaaS', subtipo: 'saas', cor: '#ec4899' },
        { nome: 'Licitação Pública', subtipo: 'licitacao', cor: '#14b8a6' },
        { nome: 'Outras Receitas', subtipo: 'outros', cor: '#6b7280' }
      ]

      categorias_despesa = [
        { nome: 'Aluguel', subtipo: 'aluguel', cor: '#ef4444' },
        { nome: 'Servidores / Hosting', subtipo: 'servidor', cor: '#f97316' },
        { nome: 'Inteligência Artificial (APIs)', subtipo: 'ia', cor: '#a855f7' },
        { nome: 'Utilidades (Água/Luz/Internet)', subtipo: 'utilidade', cor: '#eab308' },
        { nome: 'Repasse a Fornecedor', subtipo: 'repasse', cor: '#dc2626' },
        { nome: 'Antecipação a Fornecedor', subtipo: 'antecipacao_fornecedor', cor: '#b91c1c' },
        { nome: 'Boleto - Geral', subtipo: 'boleto', cor: '#78716c' },
        { nome: 'Folha de Pagamento', subtipo: 'salario', cor: '#0ea5e9' },
        { nome: 'Impostos e Taxas', subtipo: 'imposto', cor: '#64748b' },
        { nome: 'Marketing e Publicidade', subtipo: 'marketing', cor: '#d946ef' },
        { nome: 'Contador / Jurídico', subtipo: 'contador', cor: '#4b5563' },
        { nome: 'Viagem / Deslocamento', subtipo: 'viagem', cor: '#0d9488' },
        { nome: 'Material / Suprimentos', subtipo: 'material', cor: '#ca8a04' },
        { nome: 'Software / Licenças', subtipo: 'software', cor: '#7c3aed' },
        { nome: 'Outras Despesas', subtipo: 'outros', cor: '#9ca3af' }
      ]

      categorias_receita.each do |cat|
        if db[:categorias].where(nome: cat[:nome], tipo: 'receita').empty?
          db[:categorias].insert(cat.merge(tipo: 'receita'))
        end
      end

      categorias_despesa.each do |cat|
        if db[:categorias].where(nome: cat[:nome], tipo: 'despesa').empty?
          db[:categorias].insert(cat.merge(tipo: 'despesa'))
        end
      end
      puts "  ✅ Categorias de receita e despesa criadas"

      # ========================================
      # CATEGORIAS PESSOAIS
      # ========================================
      admin = db[:usuarios].where(email: 'admin@instasolutions.com.br').first
      if admin
        pessoal_cats = [
          { nome: 'Salário / Pro-labore', tipo: 'receita', cor: '#10b981' },
          { nome: 'Distribuição de Lucros', tipo: 'receita', cor: '#06b6d4' },
          { nome: 'Freelance / Extra', tipo: 'receita', cor: '#8b5cf6' },
          { nome: 'Moradia', tipo: 'despesa', cor: '#ef4444' },
          { nome: 'Alimentação', tipo: 'despesa', cor: '#f97316' },
          { nome: 'Transporte', tipo: 'despesa', cor: '#eab308' },
          { nome: 'Saúde', tipo: 'despesa', cor: '#ec4899' },
          { nome: 'Educação', tipo: 'despesa', cor: '#a855f7' },
          { nome: 'Lazer', tipo: 'despesa', cor: '#14b8a6' },
          { nome: 'Cartão de Crédito', tipo: 'despesa', cor: '#dc2626' },
          { nome: 'Investimentos', tipo: 'investimento', cor: '#0ea5e9' },
          { nome: 'Outros Pessoais', tipo: 'despesa', cor: '#9ca3af' }
        ]

        pessoal_cats.each do |cat|
          if db[:pessoal_categorias].where(nome: cat[:nome], usuario_id: admin[:id]).empty?
            db[:pessoal_categorias].insert(cat.merge(usuario_id: admin[:id]))
          end
        end
        puts "  ✅ Categorias pessoais criadas"
      end

      puts "🎉 Seeds finalizados!"
    end
  end
end
