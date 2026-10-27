// ApolloDesk — seletor de variáveis nos campos de variável dos modelos do WhatsApp.
// Vale na janela "Templates do WhatsApp" dentro da conversa e no formulário de campanha.
// Pedido do Leonardo (26–27/out/2026, E14 da APOLLO-132).
//
// Como funciona: o dashboard é compilado (Vite) e os campos são <input> com placeholder
// "Insira o valor para N" (conversa) ou "Digite um valor para N" (campanha). Este script observa
// o DOM, e para cada campo desses acrescenta um <select> com as variáveis padrão + "Personalizado".
// Escolher uma variável grava o código Liquid no input e dispara o evento que o Vue escuta;
// "Personalizado" limpa e devolve o campo para digitação. Quem resolve o código no envio é o
// servidor (campanha: LiquidTemplateProcessorService; conversa: patch ApolloVariaveisModelo).
(function () {
  'use strict';
  var RE_PLACEHOLDER = /(insira|digite)\s+(o|um)\s+valor\s+para|enter\s+(the\s+)?value\s+for/i;
  var OPCOES = [
    ['', 'Personalizado (digitar)'],
    ['{{ contact.name }}', 'Nome do contato'],
    ['{{ contact.first_name }}', 'Primeiro nome do contato'],
    ['{{ contact.phone_number }}', 'Telefone do contato'],
    ['{{ contact.email }}', 'E-mail do contato'],
    ['{{ agent.name }}', 'Nome do atendente'],
    ['{{ account.name }}', 'Nome da empresa'],
    ['{{ hora_atual }}', 'Hora atual (HH:MM)'],
    ['{{ data_atual }}', 'Data atual (dd/mm/aaaa)']
  ];

  function dispara(input, valor) {
    var setter = Object.getOwnPropertyDescriptor(window.HTMLInputElement.prototype, 'value').set;
    setter.call(input, valor);
    input.dispatchEvent(new Event('input', { bubbles: true }));
    input.dispatchEvent(new Event('change', { bubbles: true }));
  }

  function enfeita(input) {
    if (input.dataset.apolloVariavel) return;
    input.dataset.apolloVariavel = '1';
    var sel = document.createElement('select');
    sel.className = 'apollo-variavel-select';
    sel.setAttribute('aria-label', 'Variável');
    OPCOES.forEach(function (o) {
      var op = document.createElement('option');
      op.value = o[0]; op.textContent = o[1]; sel.appendChild(op);
    });
    // estado inicial: se o campo já tem um código conhecido, mostra-o selecionado
    var atual = (input.value || '').trim();
    var conhecido = OPCOES.some(function (o) { return o[0] && o[0] === atual; });
    sel.value = conhecido ? atual : '';
    input.readOnly = conhecido;
    sel.addEventListener('change', function () {
      if (sel.value) { dispara(input, sel.value); input.readOnly = true; }
      else { input.readOnly = false; dispara(input, ''); input.focus(); }
    });
    input.addEventListener('input', function () {
      var v = (input.value || '').trim();
      var c = OPCOES.some(function (o) { return o[0] && o[0] === v; });
      if (!c && sel.value) sel.value = '';
    });
    var caixa = document.createElement('div');
    caixa.className = 'apollo-variavel';
    input.parentNode.insertBefore(caixa, input);
    caixa.appendChild(sel);
    caixa.appendChild(input);
  }

  function varre(raiz) {
    var inputs = (raiz.querySelectorAll ? raiz.querySelectorAll('input[placeholder]') : []);
    for (var i = 0; i < inputs.length; i++) {
      if (RE_PLACEHOLDER.test(inputs[i].getAttribute('placeholder') || '')) enfeita(inputs[i]);
    }
  }

  var css = document.createElement('style');
  css.textContent =
    '.apollo-variavel{display:flex;gap:.5rem;align-items:center;width:100%}' +
    '.apollo-variavel > select{flex:0 0 auto;max-width:46%;min-width:11rem;height:2.5rem;border-radius:.75rem;' +
    'border:1px solid rgba(128,128,128,.35);background:transparent;color:inherit;padding:0 .5rem;font:inherit}' +
    '.apollo-variavel > input{flex:1 1 auto;min-width:0}' +
    '.apollo-variavel > input[readonly]{opacity:.75}';
  document.head.appendChild(css);

  var obs = new MutationObserver(function (muts) {
    for (var i = 0; i < muts.length; i++) {
      var ad = muts[i].addedNodes;
      for (var j = 0; j < ad.length; j++) if (ad[j].nodeType === 1) varre(ad[j]);
    }
  });
  function inicia() {
    varre(document.body);
    obs.observe(document.body, { childList: true, subtree: true });
  }
  if (document.body) inicia(); else document.addEventListener('DOMContentLoaded', inicia);
})();
