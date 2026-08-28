#!/bin/sh
# ApolloTeam — troca a paleta AZUL do Chatwoot pelo VERDE da marca Apollo.
#
# POR QUE ISTO EXISTE, E POR QUE É UM sed
# ---------------------------------------
# O Chatwoot NÃO tem tema configurável: a paleta é compilada pelo Tailwind
# direto nos bundles de `public/vite/assets/`. Foi verificado no bundle real —
# só existem as custom properties internas do Tailwind (--tw-bg-opacity e
# afins); NÃO há nenhuma variável de cor de tema para sobrescrever por CSS.
# Sem tocar no arquivo compilado, as únicas saídas seriam recompilar o
# frontend (fork completo) ou aceitar o azul.
#
# Este script roda no BUILD de uma imagem derivada — não no container em
# execução. O resultado fica assado na imagem: sobrevive a restart, é
# reproduzível e está versionado. É a diferença entre "mudança documentada" e
# "alguém mexeu no container".
#
# ⚠️ ATRELADO À TAG DA IMAGEM. Os nomes dos bundles têm hash de conteúdo e a
# paleta pode mudar de nome entre versões. Por isso o compose fixa
# chatwoot/chatwoot:v4.17.1. Ao subir de versão: rodar, conferir a contagem
# abaixo e reajustar se vier zero.
set -e

ASSETS=/app/public/vite/assets

# Azul do Chatwoot  →  Verde ApolloTeam
#
# O tom principal (#2781F6) vira #0A7D47, o verde escuro que a casa já usa no
# tema claro do ApolloMail — e NÃO o #2FE68C do ícone. O motivo é contraste:
# o emerald claro é lindo como símbolo e ilegível como fundo de botão com
# texto branco. Os tons claros da escala viram verdes claros equivalentes,
# preservando a relação de luminância do original.
MAP="
2781f6:0a7d47
3b9eff:13c36d
0090ff:0fa85c
70b8ff:34d98b
c2e5ff:a7f3c9
f4faff:f0fdf6
"
# Mesma troca na forma rgb(r g b), que o Tailwind usa quando aplica opacidade.
MAP_RGB="
39 129 246:10 125 71
59 158 255:19 195 109
0 144 255:15 168 92
112 184 255:52 217 139
194 229 255:167 243 201
244 250 255:240 253 246
"

total=0
for f in "$ASSETS"/*.css "$ASSETS"/*.js; do
  [ -f "$f" ] || continue
  antes=0
  for par in $MAP; do
    de=$(echo "$par" | cut -d: -f1)
    n=$(grep -o -i "#$de" "$f" 2>/dev/null | wc -l || true)
    antes=$((antes + n))
  done
  [ "$antes" -eq 0 ] && continue

  for par in $MAP; do
    de=$(echo "$par" | cut -d: -f1); para=$(echo "$par" | cut -d: -f2)
    # -i com sufixo vazio não é portável no BusyBox; grava em temporário.
    sed "s/#$de/#$para/gI" "$f" > "$f.tmp" && mv "$f.tmp" "$f"
  done
  echo "$MAP_RGB" | while IFS= read -r par; do
    [ -z "$par" ] && continue
    de=${par%%:*}; para=${par#*:}
    sed "s/rgb($de/rgb($para/g" "$f" > "$f.tmp" && mv "$f.tmp" "$f"
  done
  echo "  $(basename "$f"): $antes ocorrencias trocadas"
  total=$((total + antes))
done

echo "TOTAL de cores trocadas: $total"

# Conferir o EFEITO, não o exit code — regra da casa. Se o bundle mudou de
# nome ou a paleta mudou de valor, isto falha o build em vez de entregar um
# app azul com cara de rebrandizado.
if [ "$total" -lt 50 ]; then
  echo "ERRO: menos de 50 trocas. A paleta do Chatwoot provavelmente mudou nesta versao."
  echo "      Reconferir os valores em $ASSETS antes de seguir."
  exit 1
fi

# Resíduo só importa no que o navegador executa: .css e .js. Os .js.map são
# source maps de depuração, não são servidos na interface e não pintam nada —
# a primeira versão desta checagem os contava e reprovava um build correto.
resto=0
for f in "$ASSETS"/*.css "$ASSETS"/*.js; do
  [ -f "$f" ] || continue
  n=$(grep -o -i "#2781f6" "$f" 2>/dev/null | wc -l || true)
  resto=$((resto + n))
done
if [ "$resto" -ne 0 ]; then
  echo "ERRO: ainda restam $resto ocorrencias do azul principal em css/js."
  exit 1
fi
echo "OK: nenhum residuo do azul principal (#2781F6) em css/js."
