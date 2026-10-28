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
    // mesma cara do campo do Desk: herda as classes (Tailwind) do input e copia o que o CSS do Vue escopa
    sel.className = input.className + ' apollo-variavel-select';
    var cs = window.getComputedStyle(input);
    ['height', 'minHeight', 'border', 'borderRadius', 'backgroundColor', 'color', 'fontSize', 'fontFamily', 'fontWeight',
     'lineHeight', 'paddingLeft', 'boxShadow', 'outline'].forEach(function (k) { sel.style[k] = cs[k]; });
    sel.style.marginBottom = '0';
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
    // a seta mora no invólucro (posicionada no canto direito), não no select: o fundo do select
    // é pintado a partir do conteúdo e a seta ficava colada ao texto
    var inv = document.createElement('span');
    inv.className = 'apollo-variavel-inv';
    input.parentNode.insertBefore(caixa, input);
    inv.appendChild(sel);
    caixa.appendChild(inv);
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
    '.apollo-variavel{display:flex;gap:.5rem;align-items:stretch;width:100%}' +
    '.apollo-variavel-inv{position:relative;flex:0 0 auto;display:inline-flex;max-width:48%;min-width:11rem}' +
    '.apollo-variavel-inv > select.apollo-variavel-select{width:100%;cursor:pointer;margin:0;' +
    'appearance:none!important;-webkit-appearance:none!important;padding-right:2.25rem!important;background-image:none!important}' +
    '.apollo-variavel-inv::after{content:"";position:absolute;right:.85rem;top:50%;width:12px;height:8px;margin-top:-4px;pointer-events:none;' +
    'background:url("data:image/svg+xml,%3Csvg xmlns=%22http://www.w3.org/2000/svg%22 width=%2212%22 height=%228%22 viewBox=%220 0 12 8%22%3E%3Cpath d=%22M1 1.5l5 5 5-5%22 fill=%22none%22 stroke=%22%23808080%22 stroke-width=%221.6%22 stroke-linecap=%22round%22 stroke-linejoin=%22round%22/%3E%3C/svg%3E") no-repeat center/12px 8px}' +
    '.apollo-variavel > input{flex:1 1 auto;min-width:0}';
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
