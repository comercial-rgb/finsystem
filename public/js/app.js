/* FinSystem - Application JavaScript */

// Override method for PUT/DELETE forms
function submitWithMethod(form, method) {
  const input = document.createElement('input');
  input.type = 'hidden';
  input.name = '_method';
  input.value = method;
  form.appendChild(input);
  form.submit();
}

// Auto-dismiss flash messages after 5s
document.addEventListener('DOMContentLoaded', function() {
  setTimeout(function() {
    ['flash-success', 'flash-error'].forEach(function(id) {
      var el = document.getElementById(id);
      if (el) {
        el.style.transition = 'opacity 0.3s ease';
        el.style.opacity = '0';
        setTimeout(function() { el.style.display = 'none'; }, 300);
      }
    });
  }, 5000);
});

// Confirmar exclusão
function confirmarExclusao(msg) {
  return confirm(msg || 'Tem certeza que deseja excluir este registro?');
}

// Formatar moeda BRL
function formatarMoeda(valor) {
  return new Intl.NumberFormat('pt-BR', { style: 'currency', currency: 'BRL' }).format(valor);
}

// Máscara de moeda brasileira para inputs com classe 'moeda-br'
function aplicarMascaraMoeda(input) {
  let v = input.value.replace(/\D/g, '');
  if (v === '') { input.value = ''; return; }
  v = (parseInt(v, 10) / 100).toFixed(2);
  v = v.replace('.', ',');
  v = v.replace(/(\d)(?=(\d{3})+(?!\d))/g, '$1.');
  input.value = v;
}

// Converter valor BR para float (para cálculos JS)
function parseMoedaBR(valor) {
  if (!valor) return 0;
  return parseFloat(valor.replace(/\./g, '').replace(',', '.')) || 0;
}

// Aplicar máscara automaticamente em todos os inputs com classe 'moeda-br'
document.addEventListener('DOMContentLoaded', function() {
  document.querySelectorAll('.moeda-br').forEach(function(input) {
    input.addEventListener('input', function() { aplicarMascaraMoeda(this); });
    input.addEventListener('focus', function() { this.select(); });
  });
});

// Máscara simples para CPF/CNPJ
function aplicarMascaraDocumento(input) {
  var v = input.value.replace(/\D/g, '');
  if (v.length <= 11) {
    v = v.replace(/(\d{3})(\d)/, '$1.$2');
    v = v.replace(/(\d{3})(\d)/, '$1.$2');
    v = v.replace(/(\d{3})(\d{1,2})$/, '$1-$2');
  } else {
    v = v.replace(/^(\d{2})(\d)/, '$1.$2');
    v = v.replace(/^(\d{2})\.(\d{3})(\d)/, '$1.$2.$3');
    v = v.replace(/\.(\d{3})(\d)/, '.$1/$2');
    v = v.replace(/(\d{4})(\d)/, '$1-$2');
  }
  input.value = v;
}

// ========================================
// BUSCA CNPJ/CPF - Cliente e Fornecedor
// ========================================

async function buscarDocumento(tipo) {
  var input = document.getElementById(tipo + '_documento');
  if (!input) return;
  var doc = input.value.replace(/\D/g, '');
  if (!doc || doc.length < 11) return;

  aplicarMascaraDocumento(input);

  var infoDiv = document.getElementById(tipo + '_info');
  var cadastroDiv = document.getElementById(tipo + '_cadastro');
  if (infoDiv) infoDiv.classList.add('hidden');
  if (cadastroDiv) cadastroDiv.classList.add('hidden');

  var plural = tipo === 'cliente' ? 'clientes' : 'fornecedores';
  try {
    var resp = await fetch('/api/' + plural + '/buscar_documento?documento=' + doc);
    var data = await resp.json();
    if (data.success && data.encontrado) {
      document.getElementById(tipo + '_id_hidden').value = data.data.id;
      document.getElementById(tipo + '_nome_display').textContent = data.data.nome + (data.data.razao_social ? ' (' + data.data.razao_social + ')' : '');
      document.getElementById(tipo + '_doc_display').textContent = data.data.cnpj_cpf_ein || doc;
      infoDiv.classList.remove('hidden');
      return;
    }
  } catch(e) { console.error('Erro busca local:', e); }

  if (doc.length === 14) {
    try {
      var resp2 = await fetch('/api/consultar_cnpj/' + doc);
      var data2 = await resp2.json();
      if (data2.success) {
        var d = data2.data;
        document.getElementById(tipo + '_razao').value = d.razao_social || '';
        document.getElementById(tipo + '_fantasia').value = d.nome_fantasia || '';
        document.getElementById(tipo + '_email').value = d.email || '';
        document.getElementById(tipo + '_telefone').value = d.telefone || '';
        document.getElementById(tipo + '_endereco').value = [d.logradouro, d.bairro].filter(Boolean).join(' - ') || '';
        document.getElementById(tipo + '_cidade').value = d.municipio || '';
        document.getElementById(tipo + '_estado').value = d.uf || '';
        cadastroDiv.classList.remove('hidden');
        return;
      }
    } catch(e) { console.error('Erro BrasilAPI:', e); }
  }

  if (cadastroDiv) cadastroDiv.classList.remove('hidden');
}

async function criarEntidade(tipo) {
  var doc = document.getElementById(tipo + '_documento').value;
  var plural = tipo === 'cliente' ? 'clientes' : 'fornecedores';

  var body = {
    cnpj_cpf_ein: doc,
    razao_social: document.getElementById(tipo + '_razao').value,
    nome_fantasia: document.getElementById(tipo + '_fantasia').value,
    email: document.getElementById(tipo + '_email').value,
    telefone: document.getElementById(tipo + '_telefone').value,
    endereco: document.getElementById(tipo + '_endereco').value,
    cidade: document.getElementById(tipo + '_cidade').value,
    estado: document.getElementById(tipo + '_estado').value
  };

  if (!body.razao_social && !body.nome_fantasia) {
    alert('Preencha ao menos a Razão Social ou Nome Fantasia');
    return;
  }

  try {
    var resp = await fetch('/api/' + plural + '/criar_rapido', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(body)
    });
    var data = await resp.json();
    if (data.success) {
      document.getElementById(tipo + '_id_hidden').value = data.data.id;
      document.getElementById(tipo + '_nome_display').textContent = data.data.nome;
      document.getElementById(tipo + '_doc_display').textContent = doc;
      document.getElementById(tipo + '_info').classList.remove('hidden');
      document.getElementById(tipo + '_cadastro').classList.add('hidden');
    } else {
      alert('Erro ao cadastrar: ' + (data.message || 'Erro desconhecido'));
    }
  } catch(e) {
    alert('Erro de conexão: ' + e.message);
  }
}

function limparVinculo(tipo) {
  document.getElementById(tipo + '_id_hidden').value = '';
  document.getElementById(tipo + '_info').classList.add('hidden');
  document.getElementById(tipo + '_documento').value = '';
}

// ========================================
// BUSCA CNPJ - Formulários de Clientes/Fornecedores
// ========================================
async function buscarCnpjForm(inputId) {
  var input = document.getElementById(inputId);
  if (!input) return;
  var doc = input.value.replace(/\D/g, '');
  if (!doc || doc.length < 14) { alert('Informe um CNPJ válido (14 dígitos)'); return; }

  // Determinar se é cliente ou fornecedor pelo ID do campo
  var isCliente = inputId.indexOf('cliente') >= 0;
  var suffix = isCliente ? '_cliente' : '_fornecedor';

  try {
    var resp = await fetch('/api/consultar_cnpj/' + doc);
    var data = await resp.json();
    if (data.success) {
      var d = data.data;
      var rs = document.getElementById('razao_social' + suffix);
      var nf = document.getElementById('nome_fantasia' + suffix);
      var em = document.getElementById('email' + suffix);
      var te = document.getElementById('telefone' + suffix);
      var en = document.getElementById('endereco' + suffix);
      var ci = document.getElementById('cidade' + suffix);
      var es = document.getElementById('estado' + suffix);

      if (rs && !rs.value) rs.value = d.razao_social || '';
      if (nf && !nf.value) nf.value = d.nome_fantasia || '';
      if (em && !em.value) em.value = d.email || '';
      if (te && !te.value) te.value = d.telefone || '';
      if (en && !en.value) en.value = [d.logradouro, d.bairro].filter(Boolean).join(' - ') || '';
      if (ci && !ci.value) ci.value = d.municipio || '';
      if (es && !es.value) es.value = d.uf || '';

      // Also fill nome if empty
      var nome = document.querySelector('input[name="nome"]');
      if (nome && !nome.value) nome.value = d.nome_fantasia || d.razao_social || '';
    } else {
      alert('CNPJ não encontrado na base da Receita Federal');
    }
  } catch(e) {
    alert('Erro ao consultar CNPJ: ' + e.message);
  }
}
