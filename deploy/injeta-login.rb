# ApolloDesk — injeta a folha de estilo e o marcador de rota do login Apollo
# no layout da SPA. Roda no BUILD da imagem derivada.
#
# O layout é o mesmo para todas as rotas (é uma SPA), por isso o CSS é
# escopado em `body.apollo-login` e quem liga/desliga essa classe é o
# login-apollo.js.

ARQ = 'app/views/layouts/vueapp.html.erb'.freeze

html = File.read(ARQ)

# Conferir a âncora ANTES de mexer: se o Chatwoot reorganizar o layout numa
# versão nova, é melhor o build falhar aqui do que entregar uma imagem em que
# o tema simplesmente não aparece — falha silenciosa é o modo padrão desta
# stack, e um rebrand que "sobe e não aplica" custa uma rodada inteira.
abort "ERRO: </head> nao encontrado em #{ARQ} — a estrutura do layout mudou." unless html.include?('</head>')

if html.include?('login-apollo.css')
  puts 'login Apollo ja estava injetado'
  exit
end

# ⚠️ O <script> NÃO leva `defer`. Ele precisa envelopar o history.pushState
# ANTES de o vue-router carregar; com defer, a navegação da SPA saía do login
# sem remover a classe e o tema vazava para o dashboard.
TAGS = <<~HTML
    <link rel="stylesheet" href="/apollo-login/login-apollo.css">
    <script src="/apollo-login/login-apollo.js"></script>
  </head>
HTML

File.write(ARQ, html.sub('</head>', TAGS))

# Conferir o EFEITO, não o exit code — regra da casa.
final = File.read(ARQ)
ok = final.include?('login-apollo.css') && final.include?('login-apollo.js')
abort 'ERRO: a injecao nao gravou no layout.' unless ok

%w[login-apollo.css login-apollo.js login-bg.webp login-panel.webp
   apollodesk-lockup.png JetBrainsMono-Variable.woff2 VT323-Regular.woff2].each do |f|
  caminho = "public/apollo-login/#{f}"
  abort "ERRO: ativo faltando — #{caminho}" unless File.exist?(caminho)
end

puts 'login Apollo injetado no layout, com os 7 ativos no lugar'
