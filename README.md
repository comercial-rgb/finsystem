# FinSystem - Gestão Financeira Multi-Empresa

Sistema financeiro completo para gestão do grupo empresarial, desenvolvido em Ruby com Sinatra.

**URL de Produção:** `https://administracao.frotainstasolutions.com.br`

## 🏢 Empresas Suportadas
- **InstaSolutions** (BR - SP) - Plataforma de gestão de frotas e abastecimento
- **Engine Sistemas / MS Frotas** (BR - SP) - SaaS multi-vertical
- **TechTrust AutoSolutions** (US - FL) - Serviços automotivos rápidos
- **Empresa 4** - A definir

## ⚡ Funcionalidades

### Módulo Financeiro (Core)
- Lançamento diário de receitas e despesas
- Identificação de cliente por recebimento com cálculo de lucro
- Pagamento de boletos com finalidade categorizada
- Repasse a fornecedores da rede credenciada
- **Antecipação a fornecedores** - Gera automaticamente 2 movimentações (despesa do valor + receita da taxa)
- Categorias: aluguel, servidores, IA, utilidades, folha, impostos, etc.
- Vinculação a contas bancárias (Itaú, Sicredi, Banco do Brasil)
- Conciliação bancária com exportação CSV
- Paginação e busca em todas as listagens
- Gráficos interativos (Chart.js)

### Módulo de Clientes e Fornecedores
- CRUD completo de clientes (PJ/PF)
- CRUD completo de fornecedores (rede credenciada, serviços, produtos)
- Dados bancários de fornecedores para repasse
- Busca e filtros por empresa/status

### Módulo de Empresas
- 4 empresas com 2 sócios cada (porcentagens configuráveis)
- Distribuição automática de lucros por sócio
- Contas bancárias por empresa (BRL + USD)
- Visão consolidada do grupo

### Módulo de Relatórios
- Resumo consolidado mensal com filtro por empresa
- Relatório específico de antecipações
- Exportação CSV para conciliação bancária
- Resultado por categoria e por banco

### Módulo Pessoal
- Controle pessoal de receitas, despesas e investimentos
- Cálculo de "disponível para investir"
- Categorias customizáveis
- Comprovantes com upload/download
- Transações recorrentes (semanal, mensal, anual, etc.)
- Gráficos de evolução mensal
- Isolado por usuário

### Segurança
- Autenticação com BCrypt (hash de senhas)
- Sessões seguras com tokens
- 5 níveis de acesso: Admin, Gerente, Financeiro, Operador, Pessoal
- Recuperação de senha com token temporário
- Upload de comprovantes com verificação SHA256
- Log de auditoria completo
- Validação backend em todas as entidades (Services::Validation)
- Controle de sessão com expiração

## 🚀 Setup Local (Desenvolvimento)

### Pré-requisitos
- Ruby 3.2+
- Bundler

### Instalação

```bash
# Clonar repositório
git clone https://github.com/comercial-rgb/finsystem.git
cd finsystem

# Instalar dependências
bundle install

# Copiar arquivo de ambiente
cp .env.example .env

# Iniciar o servidor
ruby app.rb
```

### Acesso Local
- URL: http://localhost:4567
- **Admin Geral:**
  - Email: `admin@frotainstasolutions.com.br`
  - Senha: `FrotaInsta@2026!`
- **Admin Winner:**
  - Email: `admin@instasolutions.com.br`
  - Senha: `admin123`

> ⚠️ **Troque as senhas padrão imediatamente em produção!**

## ☁️ Deploy em Produção (Render.com)

### Passo 1 — Criar repositório no GitHub

```bash
cd "Sistema financeiro"
git init
git add .
git commit -m "FinSystem v1.0 - Deploy inicial"
git remote add origin https://github.com/comercial-rgb/finsystem.git
git branch -M main
git push -u origin main
```

### Passo 2 — Criar serviço no Render.com

1. Acesse [render.com](https://render.com) e faça login com GitHub (conta `comercial-rgb`)
2. Clique **"New +"** > **"Blueprint"**
3. Selecione o repositório `comercial-rgb/finsystem`
4. O Render lerá o `render.yaml` e criará automaticamente:
   - **Web Service** (free tier) — app Ruby/Sinatra
   - **PostgreSQL** (free tier) — banco de dados
5. Clique **"Apply"** e aguarde o deploy (~3-5 minutos)

**Alternativa manual (sem Blueprint):**
1. **New +** > **Web Service** > Conectar repo `comercial-rgb/finsystem`
2. Runtime: **Ruby**, Build: `bundle install`, Start: `bundle exec puma -C config/puma.rb`
3. Adicionar Environment Variables:
   - `RACK_ENV` = `production`
   - `SESSION_SECRET` = *(gerar com `ruby -e "require 'securerandom'; puts SecureRandom.hex(64)"`)* 
   - `DATABASE_URL` = *(copiar da instância PostgreSQL criada no Render)*
4. **New +** > **PostgreSQL** > Free tier > Anotar a **Internal Database URL**

### Passo 3 — Configurar domínio no Render

1. No dashboard do Render, abra o serviço `finsystem`
2. Vá em **Settings** > **Custom Domains**
3. Adicione: `administracao.frotainstasolutions.com.br`
4. O Render mostrará o **CNAME target** (algo como `finsystem-xxxx.onrender.com`)

### Passo 4 — Configurar DNS na GoDaddy

1. Acesse [dcc.godaddy.com](https://dcc.godaddy.com) > domínio `frotainstasolutions.com.br`
2. Vá em **DNS** > **Gerenciar DNS**
3. Adicione um registro:
   - **Tipo:** CNAME
   - **Nome:** `administracao`
   - **Valor:** `finsystem-xxxx.onrender.com` *(o valor fornecido pelo Render)*
   - **TTL:** 600 (ou padrão)
4. Aguarde propagação DNS (5-30 minutos)
5. Volte ao Render e clique **"Verify"** no domínio customizado
6. O Render gera certificado SSL automaticamente (HTTPS gratuito via Let's Encrypt)

### Passo 5 — Testando

```
https://administracao.frotainstasolutions.com.br
```

Login com:
- Email: `admin@frotainstasolutions.com.br`
- Senha: `FrotaInsta@2026!`

### Deploy Automático

Após a configuração inicial, basta fazer `git push` para o GitHub. O Render detecta automaticamente e faz o redeploy:

```bash
git add .
git commit -m "Minha alteração"
git push origin main
# Deploy automático no Render em ~2 minutos
```

## 📁 Estrutura de Pastas

```
finsystem/
├── app.rb                    # Arquivo principal (boot)
├── config.ru                 # Configuração Rack/Puma
├── Gemfile                   # Dependências
├── Procfile                  # Comando de start (Render/Heroku)
├── render.yaml               # Blueprint Render.com
├── .ruby-version             # Versão do Ruby
├── config/
│   ├── app_config.rb         # Configurações gerais
│   └── puma.rb               # Configuração do servidor
├── db/
│   ├── database.rb           # Conexão SQLite (dev) / PostgreSQL (prod)
│   ├── migrations.rb         # Criação de tabelas
│   └── seeds.rb              # Dados iniciais
├── models/                   # Camada de dados
├── controllers/              # Rotas e lógica HTTP
├── services/                 # Validação, recorrência, relatórios
├── middleware/                # Autenticação
├── helpers/                  # Formatação (moeda, data, badges)
├── views/                    # Templates ERB
│   ├── layouts/              # Layouts (app, login, senha)
│   ├── dashboard/            # Dashboard com gráficos
│   ├── movimentacoes/        # CRUD movimentações
│   ├── empresas/             # Empresas e sócios
│   ├── clientes/             # CRUD clientes
│   ├── fornecedores/         # CRUD fornecedores
│   ├── pessoal/              # Finanças pessoais
│   ├── relatorios/           # Relatórios
│   └── usuarios/             # Gestão de usuários + auditoria
├── public/
│   ├── css/app.css           # Estilos globais
│   ├── js/app.js             # JavaScript global
│   └── uploads/              # Comprovantes
└── data/                     # Banco SQLite local (gitignored)
```

## 🔐 Níveis de Acesso

| Nível       | Dashboard | Movimentações | Empresas | Relatórios | Usuários | Pessoal |
|-------------|:---------:|:-------------:|:--------:|:----------:|:--------:|:-------:|
| Admin       | ✅        | ✅            | ✅       | ✅         | ✅       | ✅      |
| Gerente     | ✅        | ✅            | ✅       | ✅         | ❌       | ✅      |
| Financeiro  | ✅        | ✅            | 👁️       | ✅         | ❌       | ✅      |
| Operador    | ✅        | ✅            | ❌       | ❌         | ❌       | ✅      |
| Pessoal     | ❌        | ❌            | ❌       | ❌         | ❌       | ✅      |

## 🛠 Tecnologias

| Camada | Tecnologia |
|--------|-----------|
| Backend | Ruby 3.2 + Sinatra 3.1 |
| ORM | Sequel 5.77 |
| Banco (dev) | SQLite3 |
| Banco (prod) | PostgreSQL (Render) |
| Frontend | ERB + Tailwind CSS (CDN) |
| Gráficos | Chart.js 4.4 |
| Auth | BCrypt + Tokens de sessão |
| Servidor | Puma 6.4 |
| Hospedagem | Render.com (free tier) |
| Domínio | GoDaddy (DNS CNAME) |
| Repositório | GitHub (comercial-rgb/finsystem) |
