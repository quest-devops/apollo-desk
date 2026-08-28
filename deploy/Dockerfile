# ApolloTeam — imagem derivada do Chatwoot com a marca Apollo assada dentro.
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
# logo.svg          → fundo claro (login, barra lateral)  → lockup grafite
# logo_dark.svg     → fundo escuro (tema escuro)          → lockup branco
# logo_thumbnail.svg→ ícone pequeno / e-mail / avatar     → ícone colorido
#
# Os caminhos são os que o Chatwoot serve em /brand-assets/ e que as linhas
# LOGO, LOGO_DARK e LOGO_THUMBNAIL da tabela installation_configs apontam.
COPY brand/logo.svg            /app/public/brand-assets/logo.svg
COPY brand/logo_dark.svg       /app/public/brand-assets/logo_dark.svg
COPY brand/logo_thumbnail.svg  /app/public/brand-assets/logo_thumbnail.svg

# ── Favicons ─────────────────────────────────────────────────────────────────
# Os ícones de aba/PWA NÃO ficam em brand-assets e NÃO são cobertos por
# InstallationConfig: são ~30 PNGs soltos em public/, referenciados direto no
# layout. Sem trocá-los, a aba do navegador continua exibindo o logo do
# Chatwoot com o nome ApolloTeam ao lado — foi exatamente o que apareceu na
# primeira verificação visual. Gerados do ícone canônico por brand/icons.
COPY brand/icons/ /app/public/

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
