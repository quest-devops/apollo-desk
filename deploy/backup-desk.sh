#!/usr/bin/env bash
# =============================================================================
# backup-desk.sh — backup da instância do ApolloDesk (Chatwoot).
#
# Faz: dump do Postgres + anexos (volume storage_data) + cópia do .env.
# O .env vai junto porque guarda SECRET_KEY_BASE e as senhas do banco e do
# Redis — sem ele o restore não remonta o stack.
#
# Uso:  backup-desk.sh            (padrões abaixo servem para a instância interna)
#
# RESTORE (resumo):
#   gunzip -c db.sql.gz | docker exec -i apollo-desk-db psql -U chatwoot -d chatwoot_production
#   docker run --rm -v apollo-desk_storage_data:/d -v $PWD:/b alpine tar xzf /b/storage.tar.gz -C /d
#   cp env.bak /root/plan-secrets/apollo-desk.env && docker compose -p apollo-desk up -d
#
# ⚠️ O REDIS NÃO É COPIADO, E ISSO É DECISÃO, NÃO ESQUECIMENTO.
# No Chatwoot ele guarda fila do Sidekiq, cache e presença — nada durável que
# já não esteja no Postgres. Restaurar um Redis antigo seria pior que não ter:
# reprocessaria jobs velhos (webhook, envio, notificação) contra um estado que
# já mudou. O que se perde numa restauração é a fila em trânsito, e isso é o
# comportamento correto.
#
# NÃO para o stack: o pg_dump é consistente por transação (snapshot MVCC) e os
# anexos são imutáveis (arquivo novo = chave nova), então cópia a quente é ok.
# Mesmo raciocínio do backup-plane.sh.
# =============================================================================
set -euo pipefail

PROJ="${PROJ:-apollo-desk}"
ENV_FILE="${ENV_FILE:-/root/plan-secrets/apollo-desk.env}"
KEEP="${KEEP:-7}"
BACKUP_DIR="${BACKUP_DIR:-/root/backups-desk}"
RCLONE_REMOTE="${RCLONE_REMOTE:-apollo-backup:apollo-backups/desk}"
# Espaço mínimo livre para começar. Em ago/2026 os backups do Nextcloud
# encheram a raiz e derrubaram serviço; desde então todo backup da casa checa
# antes de escrever, em vez de descobrir no meio.
MIN_LIVRE_MB="${MIN_LIVRE_MB:-2048}"

[ -f "$ENV_FILE" ] || { echo "ERRO: $ENV_FILE nao existe"; exit 1; }

# ⚠️ NÃO usar "set -a; . .env": um .env de Docker Compose não é script shell —
# um valor com `<` ou espaço vira redirecionamento e mata o backup inteiro.
# Ler chave a chave é o certo (a lição veio do backup-plane.sh).
envget(){ grep -E "^$1=" "$ENV_FILE" | tail -1 | cut -d= -f2-; }

DBC="${PROJ}-db"
PGUSER="$(envget POSTGRES_USERNAME)"; PGUSER="${PGUSER:-chatwoot}"
PGDB="$(envget POSTGRES_DATABASE)";   PGDB="${PGDB:-chatwoot_production}"
PGPASS="$(envget POSTGRES_PASSWORD)"

STAMP=$(date +%Y%m%d-%H%M%S)
OUT="$BACKUP_DIR/desk-$STAMP"
log(){ echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"; }

log "== backup $PROJ $STAMP =="

# 0/4 — guarda de espaço, ANTES de escrever qualquer coisa.
LIVRE_MB=$(df -Pm "$(dirname "$BACKUP_DIR")" | awk 'NR==2{print $4}')
if [ "$LIVRE_MB" -lt "$MIN_LIVRE_MB" ]; then
  log "!! ERRO: so ${LIVRE_MB}MB livres (minimo ${MIN_LIVRE_MB}MB). Abortando ANTES de escrever."
  exit 1
fi

mkdir -p "$OUT"

log "1/4 dump do Postgres ($DBC)..."
docker exec -e PGPASSWORD="$PGPASS" "$DBC" \
  pg_dump --no-owner --no-privileges -U "$PGUSER" -d "$PGDB" | gzip > "$OUT/db.sql.gz"
[ -s "$OUT/db.sql.gz" ] || { log "!! ERRO: dump vazio"; exit 1; }

# ⚠️ Conferir o EFEITO, não o exit code. Um pipe com pg_dump pode sair 0 e
# gravar um .gz truncado; sem este teste o erro só aparece no dia do restore.
log "2/4 verificando integridade do dump..."
gzip -t "$OUT/db.sql.gz" || { log "!! ERRO: db.sql.gz corrompido"; exit 1; }
# E conferir que o dump tem CONTEUDO, não só um cabeçalho válido.
TABELAS=$(gunzip -c "$OUT/db.sql.gz" | grep -c '^CREATE TABLE' || true)
if [ "$TABELAS" -lt 50 ]; then
  log "!! ERRO: dump com apenas $TABELAS tabelas (esperado ~100+). Backup suspeito."
  exit 1
fi
log "  ok: $TABELAS tabelas no dump"

log "3/4 anexos (volume ${PROJ}_storage_data)..."
docker run --rm -v "${PROJ}_storage_data":/d:ro -v "$OUT":/b alpine \
  tar czf /b/storage.tar.gz -C /d . >/dev/null 2>&1 || log "  (aviso: volume de anexos vazio ou ausente)"

log "4/4 .env (segredos p/ remontar o stack)..."
cp "$ENV_FILE" "$OUT/env.bak"
chmod 600 "$OUT/env.bak"

# rotação local
ls -1dt "$BACKUP_DIR"/desk-* 2>/dev/null | tail -n +$((KEEP+1)) | xargs -r rm -rf

log "== OK: $OUT ($(du -sh "$OUT" | cut -f1)) — mantendo os ultimos $KEEP =="

# OFF-SITE: falha aqui é ERRO (exit != 0), nunca aviso silencioso.
# Foi exatamente o "aviso silencioso" que deixou a produção 2 dias sem cópia
# externa em agosto.
if [ -z "$RCLONE_REMOTE" ]; then
  log "!! ATENCAO: off-site NAO configurado — este backup existe SO neste servidor."
  exit 0
fi
if ! command -v rclone >/dev/null 2>&1; then
  log "!! ERRO: RCLONE_REMOTE definido mas rclone NAO esta instalado."
  exit 1
fi
log "off-site: rclone copy -> $RCLONE_REMOTE/desk-$STAMP"
if rclone copy "$OUT" "$RCLONE_REMOTE/desk-$STAMP"; then
  log "off-site OK"
  rclone delete --min-age 31d "$RCLONE_REMOTE" --rmdirs >/dev/null 2>&1 || true
else
  log "!! ERRO: off-site FALHOU (destino $RCLONE_REMOTE). Backup existe SO no servidor."
  exit 1
fi
