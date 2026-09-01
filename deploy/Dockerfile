# ApolloDesk — imagem derivada do Chatwoot com a marca Apollo assada dentro.
#
# Por que uma imagem derivada, e não `docker exec` no container: mudança feita
# no container em execução some no primeiro `docker compose pull` e não está
# em lugar nenhum do git. Aqui o rebrand é um artefato versionado e o build é
# reproduzível — a regra da casa ("mudou algo no container, atualize o
# artefato do deploy no mesmo commit") passa a ser automática.
#
# ⚠️ A TAG É FIXA DE PROPÓSITO. O script de cores depende dos bundles
# compilados desta versão. Ao subir de versão, o build FALHA em vez de
# entregar um app meio azul — ver rebrand-cores.rb.
FROM chatwoot/chatwoot:v4.17.1

# ── Logos ────────────────────────────────────────────────────────────────────
# logo.svg          → lockup VERDE (emerald inteiro)
# logo_dark.svg     → lockup verde-bicolor (Apollo branco + Desk emerald)
# logo_thumbnail.svg→ ícone colorido (pequeno / e-mail / avatar)
#
# ⚠️ POR QUE O `logo.svg` É O VERDE, E NÃO O GRAFITE.
# Verificado na tela: a página de LOGIN usa `LOGO` nos DOIS temas — ela nunca
# troca para `LOGO_DARK`. Com o lockup grafite (#202020) ali, o resultado no
# tema escuro era um wordmark invisível sobre fundo #1C1D20.
# Das quatro variantes, só a VERDE é legível nos dois fundos: o grafite some no
# escuro, e o branco e o bicolor somem no claro (o "Apollo" é quase branco).
# O `LOGO_DARK` segue apontando para o bicolor, que é o certo nos pontos do
# app que de fato honram o tema.
#
# Os caminhos são os que o Chatwoot serve em /brand-assets/ e que as linhas
# LOGO, LOGO_DARK e LOGO_THUMBNAIL da tabela installation_configs apontam.
# ⚠️ OS ATIVOS VÃO COM NOME VERSIONADO, e este é o motivo — custou duas
# rodadas de "a logo continua a do Chatwoot":
#
# O Rails serve /brand-assets/ com Cache-Control de UM ANO. Enquanto os nossos
# arquivos usavam os nomes originais (logo.svg, logo_thumbnail.svg), o
# navegador de quem já tinha aberto o app continuava exibindo o balão azul do
# Chatwoot — o arquivo no servidor estava certo, a cópia no cliente não. E
# baixar o cabeçalho para `no-cache` no Caddy só vale para buscas NOVAS: a
# entrada já gravada foi salva com o max-age antigo e não revalida sozinha.
#
# Nome novo = URL nova = nenhum cache antigo para atrapalhar. É o que o
# Chatwoot faz com os próprios bundles, e o que faltava aqui. Ao trocar a
# marca de novo, subir o sufixo e ajustar o set-marca.rb junto — foi o que
# aconteceu em 28/ago quando o produto passou de ApolloTeam para ApolloDesk
# (v2 -> v3).
COPY brand/logo.svg            /app/public/brand-assets/apollodesk-logo-v4.svg
COPY brand/logo_dark.svg       /app/public/brand-assets/apollodesk-logo-dark-v4.svg
COPY brand/logo_thumbnail.svg  /app/public/brand-assets/apollodesk-icone-v4.svg

# Os nomes originais também são substituídos, para qualquer ponto do código
# que os referencie direto sem passar por InstallationConfig.
COPY brand/logo.svg            /app/public/brand-assets/logo.svg
COPY brand/logo_dark.svg       /app/public/brand-assets/logo_dark.svg
COPY brand/logo_thumbnail.svg  /app/public/brand-assets/logo_thumbnail.svg

# ── Favicons ─────────────────────────────────────────────────────────────────
# Os ícones de aba/PWA NÃO ficam em brand-assets e NÃO são cobertos por
# InstallationConfig: são ~30 PNGs soltos em public/, referenciados direto no
# layout. Sem trocá-los, a aba do navegador continua exibindo o logo do
# Chatwoot com o nome do produto ao lado — foi exatamente o que apareceu na
# primeira verificação visual. Gerados do ícone canônico por brand/icons.
COPY brand/icons/ /app/public/

# ── Tela de login no padrão Apollo ───────────────────────────────────────────
# Réplica do tema "terminal emerald" do ApolloAuth, o mesmo já portado para o
# ApolloMail. É CSS sobre o DOM existente, não um componente novo: reescrever
# a tela de login (que é um componente Vue compilado) exigiria fork do
# frontend e build do Vite a cada release — a dívida que decidimos não pegar.
COPY brand/login/ /app/public/apollo-login/

COPY deploy/injeta-login.rb /tmp/injeta-login.rb
RUN ruby /tmp/injeta-login.rb && rm /tmp/injeta-login.rb

# ── Paleta: azul do Chatwoot → verde da Apollo ───────────────────────────────
COPY deploy/rebrand-cores.rb /tmp/rebrand-cores.rb
RUN ruby /tmp/rebrand-cores.rb && rm /tmp/rebrand-cores.rb

# ⚠️ NÃO acrescentar `USER` aqui. A imagem oficial do Chatwoot roda como ROOT
# (`docker inspect chatwoot/chatwoot:v4.17.1` devolve User vazio) e o
# entrypoint precisa escrever em /app: ele roda `bundle install`, mexe em
# /app/Gemfile.lock e cria /app/tmp/cache. Uma tentativa de "endurecer" isto
# com `USER 1000` + chown pôs o container em restart loop com
# `Permission denied @ dir_s_mkdir - /app/tmp/cache`.
# Se um dia for para rodar sem root, é mudança do entrypoint — não uma linha
# a mais no fim do Dockerfile.
