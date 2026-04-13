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
