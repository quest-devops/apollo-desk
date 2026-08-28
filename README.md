# apollo-desk

Deploy e (futuramente) o fork do **ApolloDesk** — central de atendimento omnichannel da Apollo, sobre **Chatwoot**.

> **O porquê não mora aqui.** Decisões, armadilhas e estado da frente ficam no contexto vivo:
> `apollo-solution/apps/desk/README.md` (e o comparativo da base em `pesquisa-produto-base.md`).
> Aqui fica o **quê**. ApolloPlan: **APOLLO-132** (etapas E0–E7 · APOLLO-133 a 140).

## O que este repo contém

| | |
|---|---|
| `deploy/docker-compose.yml` | stack do lab: Postgres (pgvector) + Redis + Rails + Sidekiq |
| `deploy/.env.example` | modelo de configuração — o `.env` real **nunca** entra no git |
| `deploy/caddy-vhost.snippet` | bloco para o Caddyfile compartilhado do `apollo-cloud` |

## As três armadilhas que já custaram tempo em outros apps

1. **`DISABLE_ENTERPRISE=true` desde o primeiro boot.** Sem isso o
   `Internal::ReconcilePlanConfigService` reseta logo e nome para "Chatwoot" —
   em background, então o rebrand *parece* ter funcionado e some depois.
2. **`pgvector`, não Postgres puro.** As migrations criam a extensão `vector`
   independentemente da flag de enterprise.
3. **HTTPS desde o começo.** URL de widget, webhook e callback são derivadas do
   `FRONTEND_URL`; a Meta recusa webhook que não seja https.

## Subir

```bash
docker compose -f deploy/docker-compose.yml --env-file deploy/.env up -d
docker network connect apollo-desk_default apollo-cloud-caddy-1   # uma vez
```

Segredos moram em `/root/plan-secrets/apollo-desk.env` (600), gerados **no servidor**.

## Licença

O Chatwoot é **MIT** no core. Este deploy remove o diretório `enterprise/` do
comportamento em runtime (`DISABLE_ENTERPRISE=true`), o que mantém a instalação
100% MIT — a base legal do rebrand. O *copyright notice* MIT é preservado no
fonte, e a marca "Chatwoot" não é usada na revenda.
