// ApolloDesk — relatório de campanhas de WhatsApp na tela (ver deploy/patch-campanhas.rb).
// Pedido do Leonardo (28/out/2026), E16 da APOLLO-132.
//
// O front do Chatwoot 4.17 já tem a página de relatório (rota campaigns_whatsapp_analytics), mas
// 1) esconde o botão que leva a ela quando a instalação não é enterprise (isEnterprise no CampaignList);
// 2) não tem tradução pt-BR para a página (apareceriam as chaves CAMPAIGN.WHATSAPP.ANALYTICS.*);
// 3) não mostra quem RESPONDEU nem exporta.
// Este script resolve os três por fora do bundle: injeta o botão nos cards, funde as traduções no
// vue-i18n em tempo de execução, acrescenta o card "Responderam" e o botão "Exportar CSV".
(function () {
  'use strict';

  var TRADUCAO = {
    CAMPAIGN: { WHATSAPP: {
      CARD: { ANALYTICS: 'Relatório da campanha' },
      ANALYTICS: {
        LOADING: 'Carregando o relatório…',
        EMPTY: 'Nenhum registro de envio.',
        EMPTY_FILTER: 'Nenhum registro com status {status}.',
        DELIVERIES_ERROR: 'Não foi possível carregar os envios. Atualize a página.',
        EMPTY_STATE: {
          ERROR: { TITLE: 'Não foi possível carregar o relatório', DESCRIPTION: 'Atualize a página para tentar de novo.' },
          PENDING: { TITLE: 'Os dados aparecem assim que o envio começar', DESCRIPTION: 'Ainda não há registros de envio para esta campanha.' },
          UNAVAILABLE: { TITLE: 'Relatório indisponível para esta campanha', DESCRIPTION: 'Nenhum envio foi registrado. Acontece com campanhas disparadas antes do relatório existir (antes de 28/10/2026).' }
        },
        PROCESSING_BANNER: {
          DEFAULT: 'A campanha ainda está sendo enviada. O relatório atualiza sozinho.',
          BOTH: 'A campanha ainda está sendo enviada: {queued} mensagens na fila e {awaitingUpdate} aguardando confirmação do WhatsApp.',
          BOTH_SINGLE: 'A campanha ainda está sendo enviada: {queued} mensagem na fila e {awaitingUpdate} aguardando confirmação do WhatsApp.',
          BOTH_QUEUED_SINGLE: 'A campanha ainda está sendo enviada: {queued} mensagem na fila e {awaitingUpdate} aguardando confirmação do WhatsApp.',
          BOTH_AWAITING_SINGLE: 'A campanha ainda está sendo enviada: {queued} mensagens na fila e {awaitingUpdate} aguardando confirmação do WhatsApp.',
          QUEUED: 'A campanha ainda está sendo enviada: {count} mensagem na fila. | A campanha ainda está sendo enviada: {count} mensagens na fila.',
          AWAITING_UPDATE: 'A campanha ainda está sendo enviada: {count} mensagem aguardando confirmação do WhatsApp. | A campanha ainda está sendo enviada: {count} mensagens aguardando confirmação do WhatsApp.',
          COMPLETING: 'A campanha está terminando. O relatório atualiza sozinho.'
        },
        RATE: '{value}% da audiência',
        SENT_ON: 'Enviada em {date}',
        PAGE_INFO: 'Mostrando {startItem} - {endItem} de {totalItems} contato | Mostrando {startItem} - {endItem} de {totalItems} contatos',
        BREADCRUMB: { CAMPAIGNS: 'Campanhas', WHATSAPP: 'WhatsApp' },
        FILTERS: { ALL: 'Todos' },
        METRICS: {
          AUDIENCE: { LABEL: 'Audiência', HINT: 'Contatos das etiquetas desta campanha.' },
          SENT: { LABEL: 'Aceitos pelo WhatsApp', HINT: 'Mensagens que a Meta aceitou para entrega.' },
          DELIVERED: { LABEL: 'Entregues', HINT: 'Chegaram ao aparelho do contato (inclui as lidas).' },
          READ: { LABEL: 'Lidas', HINT: 'Abertas pelo contato.' },
          FAILED: { LABEL: 'Falharam', HINT: 'A Meta não conseguiu entregar. Veja o motivo na lista.' },
          SKIPPED: { LABEL: 'Pulados', HINT: 'Contatos sem telefone, não foram enviados.' }
        },
        STATUS: { QUEUED: 'Na fila', SENT: 'Aguardando entrega', DELIVERED: 'Entregue', READ: 'Lida', FAILED: 'Falhou', SKIPPED: 'Pulado' },
        BREAKDOWN: {
          TITLE: 'Resultado da entrega', DELIVERY_RATE: '{value}% entregues',
          LEGEND: { READ: 'Lidas', DELIVERED: 'Entregues', FAILED: 'Falharam', SKIPPED: 'Pulados', PENDING: 'Na fila ou aguardando' }
        },
        TABLE: { TITLE: 'Envios', CONTACT: 'Contato', STATUS: 'Status', MESSAGE: 'Mensagem', MESSAGE_NOT_GENERATED: 'Não gerada', REASON: 'Motivo', ERROR_CODE: 'Código {code}' }
      }
    } }
  };

  // ---- utilidades ----
  function app() { var el = document.getElementById('app'); return el && el.__vue_app__; }
  function contaId() { var m = location.pathname.match(/\/app\/accounts\/(\d+)/); return m ? m[1] : null; }
  function cabecalhos() {
    try {
      var par = document.cookie.split('; ').filter(function (c) { return c.indexOf('cw_d_session_info=') === 0; })[0];
      if (!par) return {};
      var h = JSON.parse(decodeURIComponent(par.slice('cw_d_session_info='.length)));
      return { 'access-token': h['access-token'], client: h.client, uid: h.uid, 'token-type': h['token-type'] || 'Bearer' };
    } catch (e) { return {}; }
  }
  function api(caminho) {
    return fetch('/api/v1/accounts/' + contaId() + caminho, { headers: cabecalhos(), credentials: 'same-origin' });
  }
  function navega(rota) {
    var a = app();
    var r = a && a.config && a.config.globalProperties && a.config.globalProperties.$router;
    if (r) r.push(rota); else location.assign(rota);
  }

  // ---- 1) traduções (vue-i18n expõe a instância em app.__VUE_I18N__) ----
  var traduzido = false;
  function traduz() {
    if (traduzido) return;
    var a = app();
    var i18n = a && a.__VUE_I18N__;
    if (!i18n || !i18n.global || !i18n.global.mergeLocaleMessage) return;
    ['pt_BR', 'pt'].forEach(function (loc) { try { i18n.global.mergeLocaleMessage(loc, TRADUCAO); } catch (e) { /* idioma não carregado */ } });
    traduzido = true;
  }

  // ---- 2) botão do relatório nos cards da lista de campanhas de WhatsApp ----
  var cacheCampanhas = { conta: null, lista: null, quando: 0 };
  function campanhas() {
    var conta = contaId();
    if (cacheCampanhas.conta === conta && cacheCampanhas.lista && Date.now() - cacheCampanhas.quando < 15000) return Promise.resolve(cacheCampanhas.lista);
    return api('/campaigns').then(function (r) { return r.ok ? r.json() : []; }).then(function (lista) {
      cacheCampanhas = { conta: conta, lista: lista, quando: Date.now() };
      return lista;
    }).catch(function () { return []; });
  }
  function botaoRelatorio(modelo, campanha) {
    var b = modelo.cloneNode(true);
    b.dataset.apolloRelatorio = String(campanha.id);
    b.title = 'Relatório da campanha';
    b.setAttribute('aria-label', 'Relatório da campanha');
    var icone = b.querySelector('[class*="i-lucide-"]');
    if (icone) icone.className = icone.className.replace(/i-lucide-[\w-]+/, 'i-lucide-chart-no-axes-column');
    b.addEventListener('click', function (ev) {
      ev.preventDefault(); ev.stopPropagation();
      navega('/app/accounts/' + contaId() + '/campaigns/whatsapp/' + campanha.id + '/analytics');
    });
    return b;
  }
  function enfeitaLista() {
    if (!/\/campaigns\/whatsapp\/?$/.test(location.pathname)) return;
    var grupos = document.querySelectorAll('div.flex.items-center.justify-end.w-20.gap-2');
    if (!grupos.length) return;
    campanhas().then(function (lista) {
      var elegiveis = lista.filter(function (c) {
        return c.inbox && c.inbox.channel_type === 'Channel::Whatsapp' && (c.campaign_status === 'completed' || c.campaign_status === 'processing');
      });
      var usados = {};
      grupos.forEach(function (g) {
        if (g.querySelector('[data-apollo-relatorio]')) return;
        var card = g.parentElement; for (var i = 0; i < 4 && card && card.innerText.trim().length < 3; i++) card = card.parentElement;
        var texto = card ? card.innerText : '';
        var alvo = elegiveis.filter(function (c) { return !usados[c.id] && texto.indexOf(c.title) >= 0; })[0];
        if (!alvo) return;
        usados[alvo.id] = true;
        var modelo = g.querySelector('button');
        if (!modelo) return;
        g.insertBefore(botaoRelatorio(modelo, alvo), g.firstChild);
      });
    });
  }

  // ---- 3) página do relatório: card "Responderam" + "Exportar CSV" ----
  function campanhaDaRota() { var m = location.pathname.match(/\/campaigns\/whatsapp\/(\d+)\/analytics/); return m ? m[1] : null; }
  var metricasTimer = null;
  function atualizaRespondeu() {
    var id = campanhaDaRota();
    if (!id) { if (metricasTimer) { clearInterval(metricasTimer); metricasTimer = null; } return; }
    api('/campaigns/' + id + '/analytics/metrics').then(function (r) { return r.ok ? r.json() : null; }).then(function (m) {
      if (!m) return;
      var card = document.querySelector('[data-apollo-respondeu]');
      if (!card) return;
      var valor = card.querySelector('[data-apollo-valor]');
      var taxa = card.querySelector('[data-apollo-taxa]');
      if (valor) valor.textContent = String(m.responded || 0);
      if (taxa) taxa.textContent = m.audience ? Math.round(((m.responded || 0) / m.audience) * 100) + '% da audiência' : '';
    }).catch(function () { /* sem rede: mantém o valor anterior */ });
  }
  function enfeitaRelatorio() {
    var id = campanhaDaRota();
    if (!id) return;
    // card: clona o último card de métrica (mesmo visual) e troca os textos
    var cards = document.querySelectorAll('div.flex.flex-col.gap-3.p-5.group.bg-n-solid-1');
    if (cards.length >= 6 && !document.querySelector('[data-apollo-respondeu]')) {
      var ultimo = cards[cards.length - 1];
      var novo = ultimo.cloneNode(true);
      novo.dataset.apolloRespondeu = '1';
      var rotulo = novo.querySelector('span.text-sm.font-medium');
      if (rotulo) rotulo.textContent = 'Responderam';
      var dica = novo.querySelector('.cursor-help');
      if (dica) { dica.setAttribute('title', 'Contatos que mandaram mensagem depois de receber a campanha.'); }
      var grande = novo.querySelector('span.text-3xl');
      if (grande) { grande.textContent = '…'; grande.dataset.apolloValor = '1'; }
      var pequeno = novo.querySelector('span.text-sm.font-medium.tabular-nums');
      if (pequeno) { pequeno.textContent = ''; pequeno.dataset.apolloTaxa = '1'; }
      else if (grande && grande.parentElement) {
        var p = document.createElement('span'); p.className = 'text-sm font-medium tabular-nums text-n-slate-11'; p.dataset.apolloTaxa = '1';
        grande.parentElement.appendChild(p);
      }
      ultimo.parentElement.appendChild(novo);
      atualizaRespondeu();
      if (!metricasTimer) metricasTimer = setInterval(atualizaRespondeu, 5000);
    }
    // botão de exportação no cabeçalho (ao lado da trilha de navegação)
    var cab = document.querySelector('header .flex.items-center.justify-between');
    if (cab && !cab.querySelector('[data-apollo-csv]')) {
      var b = document.createElement('button');
      b.type = 'button';
      b.dataset.apolloCsv = '1';
      b.textContent = 'Exportar CSV';
      b.className = 'apollo-csv';
      b.addEventListener('click', function () {
        b.disabled = true; b.textContent = 'Gerando…';
        api('/campaigns/' + id + '/analytics/contacts?formato=csv').then(function (r) { return r.blob(); }).then(function (blob) {
          var url = URL.createObjectURL(blob);
          var a = document.createElement('a'); a.href = url; a.download = 'campanha-' + id + '.csv'; document.body.appendChild(a); a.click(); a.remove();
          setTimeout(function () { URL.revokeObjectURL(url); }, 5000);
        }).catch(function () { alert('Não foi possível gerar o CSV.'); })
          .then(function () { b.disabled = false; b.textContent = 'Exportar CSV'; });
      });
      cab.appendChild(b);
    }
  }

  var css = document.createElement('style');
  css.textContent =
    '.apollo-csv{font:inherit;font-size:.875rem;font-weight:500;padding:.375rem .75rem;border-radius:.5rem;cursor:pointer;' +
    'border:1px solid rgba(128,128,128,.35);background:transparent;color:inherit;white-space:nowrap}' +
    '.apollo-csv:hover{background:rgba(128,128,128,.12)}.apollo-csv:disabled{opacity:.6;cursor:default}';
  document.head.appendChild(css);

  // ---- laço: a SPA troca de tela sem recarregar; o observer cobre tudo ----
  var agendado = null;
  function roda() {
    agendado = null;
    traduz();
    enfeitaLista();
    enfeitaRelatorio();
  }
  function agenda() { if (!agendado) agendado = setTimeout(roda, 150); }
  var obs = new MutationObserver(agenda);
  function inicia() { roda(); obs.observe(document.body, { childList: true, subtree: true }); }
  if (document.body) inicia(); else document.addEventListener('DOMContentLoaded', inicia);
})();
