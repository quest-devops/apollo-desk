/*
 * ApolloDesk — marca o <body> quando a rota é de autenticação, para o
 * login-apollo.css saber onde aplicar.
 *
 * POR QUE PRECISA DISTO
 * ---------------------
 * O Chatwoot é uma SPA: o mesmo documento (e o mesmo <main>) serve o login e
 * o app inteiro, e o Rails entrega o mesmo layout para todas as rotas. Sem um
 * marcador, o CSS do login vazaria para o dashboard — nebulosa de fundo,
 * fonte monoespaçada e tudo.
 *
 * É de propósito a coisa mais burra possível: só liga e desliga uma classe.
 * Nada de manipular o DOM do login, porque aí passaríamos a depender da
 * estrutura interna do componente Vue e o upgrade de versão viraria roleta.
 */
(function () {
  'use strict';

  // /app/login, /app/auth/reset/password, /app/auth/password/edit...
  var ROTAS = /^\/app\/(login|auth\/|signup)/;

  function aplica() {
    var eLogin = ROTAS.test(window.location.pathname);
    document.body.classList.toggle('apollo-login', eLogin);
  }

  // A navegação da SPA não dispara `popstate` — quem troca a rota é o
  // history.pushState do vue-router. Envelopamos os dois para reagir também
  // a isso; sem esse trecho, sair do login para o dashboard mantinha o tema.
  ['pushState', 'replaceState'].forEach(function (metodo) {
    var original = history[metodo];
    history[metodo] = function () {
      var r = original.apply(this, arguments);
      aplica();
      return r;
    };
  });
  window.addEventListener('popstate', aplica);

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', aplica);
  } else {
    aplica();
  }
})();
