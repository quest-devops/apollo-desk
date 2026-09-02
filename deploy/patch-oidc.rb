# ApolloDesk — acrescenta login OIDC (ApolloAuth) ao Chatwoot.
#
# Roda no BUILD da imagem derivada. É o ÚNICO ponto em que tocamos o código do
# Chatwoot; todo o resto do rebrand é configuração ou CSS.
#
# POR QUE ESTE PATCH EXISTE
# -------------------------
# O Chatwoot não tem OIDC em edição nenhuma: o core MIT traz só Devise
# (e-mail/senha) e Google OAuth2, e o SAML mora em enterprise/, atrás do plano
# de US$ 99/agente/mês. Como a remoção dessa mesma pasta é o que faz a marca
# Apollo sobreviver, pagar o SAML não era opção — ver o README do app.
#
# POR QUE ELE É TÃO PEQUENO
# -------------------------
# Porque a arquitetura do Chatwoot ajuda, e isso foi verificado antes de
# escrever qualquer linha:
#
#   - o DeviseOverrides::OmniauthCallbacksController é AGNÓSTICO DE PROVIDER:
#     ele casa o usuário por `User.from_email`, que já faz downcase. Não
#     precisa de mapping customizado no Authentik nem de código de callback.
#   - a rota `omniauth_callbacks` já está registrada para TODOS os providers
#     do Devise, então `/omniauth/openid_connect` nasce pronto.
#   - o botão já existe na nossa tela de login (brand/login/login-apollo.js).
#
# Sobram três edições: o gem, o provider e a lista de providers do modelo.
#
# ⚠️ JIT DE PROPÓSITO DESLIGADO. Com ENABLE_ACCOUNT_SIGNUP=false, usuário
# desconhecido recebe `no-account-found` em vez de ser criado. É a lição cara
# do ApolloCRM: com JIT ligado e claim que não casa, o app cria usuário
# DUPLICADO em silêncio. Falha visível é melhor que sucesso errado.

def edita(caminho, descricao)
  original = File.read(caminho)
  novo = yield(original)
  if novo.nil?
    puts "  = #{descricao}: já aplicado"
    return
  end
  File.write(caminho, novo)
  puts "  + #{descricao}"
end

puts '── aplicando o patch de OIDC ──────────────'

# 1) O gem ──────────────────────────────────────────────────────────────────
edita('Gemfile', 'Gemfile: gem omniauth_openid_connect') do |s|
  next nil if s.include?('omniauth_openid_connect')

  ancora = "gem 'omniauth-rails_csrf_protection'"
  abort "ERRO: ancora nao encontrada no Gemfile (#{ancora}) — a estrutura mudou." unless s.include?(ancora)

  s.sub(ancora, "gem 'omniauth_openid_connect'\n#{ancora}")
end

# 2) O provider ─────────────────────────────────────────────────────────────
edita('config/initializers/omniauth.rb', 'omniauth.rb: provider :openid_connect') do |s|
  next nil if s.include?(':openid_connect')

  ancora = "    provider_ignores_state: true\n  }\nend"
  abort 'ERRO: ancora nao encontrada em omniauth.rb — a estrutura mudou.' unless s.include?(ancora)

  novo_bloco = <<~'RUBY'
        provider_ignores_state: true
      }

      # ── ApolloAuth (OIDC) ─────────────────────────────────────────────────
      # Registrado só quando configurado: assim a MESMA imagem serve uma
      # instância sem SSO, sem quebrar no boot.
      if ENV['OIDC_ISSUER'].present?
        provider :openid_connect, {
          name: :openid_connect,
          issuer: ENV.fetch('OIDC_ISSUER'),
          # O Authentik publica .well-known por provider; discovery evita
          # cravar authorize/token/userinfo aqui e sair do ar se mudarem.
          discovery: true,
          scope: %i[openid email profile],
          response_type: :code,
          # O casamento do usuário é por e-mail — é o que o
          # OmniauthCallbacksController usa (User.from_email).
          uid_field: 'email',
          client_options: {
            identifier: ENV.fetch('OIDC_CLIENT_ID'),
            secret: ENV.fetch('OIDC_CLIENT_SECRET'),
            redirect_uri: "#{ENV.fetch('FRONTEND_URL')}/omniauth/openid_connect/callback"
          }
        }
      end
    end
  RUBY

  s.sub(ancora, novo_bloco.rstrip)
end

# 3) A lista de providers do modelo ─────────────────────────────────────────
edita('app/models/user.rb', 'user.rb: omniauth_providers') do |s|
  next nil if s.include?(':openid_connect')

  ancora = 'omniauth_providers: [:google_oauth2, :saml]'
  abort 'ERRO: ancora nao encontrada em user.rb — a estrutura mudou.' unless s.include?(ancora)

  s.sub(ancora, 'omniauth_providers: [:google_oauth2, :saml, :openid_connect]')
end

# 4) A sessao nao aguenta o hash de autenticacao do OIDC ────────────────────
edita('app/controllers/devise_overrides/omniauth_callbacks_controller.rb',
      'omniauth_callbacks: enxuga o auth hash antes da sessao') do |s|
  next nil if s.include?('def redirect_callbacks')

  ancora = "class DeviseOverrides::OmniauthCallbacksController < DeviseTokenAuth::OmniauthCallbacksController
  include EmailHelper
"
  abort 'ERRO: ancora nao encontrada no omniauth_callbacks_controller.' unless s.include?(ancora)

  metodo = <<~'RUBY'

    # ⚠️ SEM ISTO O LOGIN OIDC MORRE COM 500 — e o erro nao diz "OIDC".
    #
    # O devise_token_auth guarda o hash de autenticacao INTEIRO na sessao, que
    # no Chatwoot e uma sessao em COOKIE (limite de 4 KB). Com Google OAuth o
    # hash e pequeno e passa; com OIDC ele carrega `extra` (id_token cru mais o
    # userinfo) e `credentials` (access/refresh/id token) e estoura:
    #
    #   ActionDispatch::Cookies::CookieOverflow
    #     (_chatwoot_session cookie overflowed with size 7252 bytes)
    #
    # Nada disso e usado: o omniauth_success so le info.email (e name/image no
    # cadastro, que esta desligado). Entao esvaziamos os dois antes que o
    # devise_token_auth os empurre para o cookie.
    #
    # A alternativa seria mudar a sessao para o Redis — resolve tambem, mas
    # mexe no comportamento do app inteiro para consertar um caso. Este recorte
    # e menor e nao muda nada do resto.
    def redirect_callbacks
      auth = request.env['omniauth.auth']
      if auth.present?
        auth['extra'] = {}
        auth['credentials'] = {}
      end
      super
    end
  RUBY

  s.sub(ancora, ancora + metodo)
end

# ── Conferir o EFEITO, não o exit code ─────────────────────────────────────
puts
puts '── conferindo ─────────────────────────────'
checagens = {
  'Gemfile' => 'omniauth_openid_connect',
  'config/initializers/omniauth.rb' => 'provider :openid_connect',
  'app/models/user.rb' => ':openid_connect',
  'app/controllers/devise_overrides/omniauth_callbacks_controller.rb' => 'def redirect_callbacks'
}
falhas = checagens.reject { |arq, trecho| File.read(arq).include?(trecho) }
checagens.each_key { |arq| puts format('  %-34s %s', arq, falhas.key?(arq) ? 'FALHOU' : 'ok') }
abort "ERRO: #{falhas.size} arquivo(s) sem o patch." if falhas.any?

puts
puts 'patch de OIDC aplicado.'
