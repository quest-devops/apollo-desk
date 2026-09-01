# Ativos e licenças de terceiros

## Base

**Chatwoot** — [`chatwoot/chatwoot`](https://github.com/chatwoot/chatwoot), **MIT** no core.
Este repositório contém **deploy e personalização**, não o fonte do Chatwoot. A imagem é
derivada da oficial (`chatwoot/chatwoot:v4.17.1`) com o diretório `enterprise/` **desligado
em runtime** (`DISABLE_ENTERPRISE=true`), o que mantém a instalação 100% MIT — a base legal
do rebrand. O *copyright notice* MIT é preservado no fonte, e a marca "Chatwoot" não é usada
na revenda.

## Fontes (`brand/login/`)

| Arquivo | Fonte | Licença |
|---|---|---|
| `JetBrainsMono-Variable.woff2` | [JetBrains Mono](https://github.com/JetBrains/JetBrainsMono) | SIL Open Font License 1.1 |
| `VT323-Regular.woff2` | [VT323](https://fonts.google.com/specimen/VT323) (Peter Hull) | SIL Open Font License 1.1 |

A OFL permite redistribuição, inclusive embutida — desde que as fontes não sejam vendidas
isoladamente e o aviso de licença acompanhe. Este arquivo cumpre esse papel.

## Arte de fundo do login

`brand/login/login-bg.webp` e `brand/login/login-panel.webp` (a nebulosa) são **arte da
Apollo**, confirmado pelo Leonardo em 01/set/2026. Vieram do kit de marca, via
`apollo-mail-webui`, e são as mesmas usadas no ApolloAuth e no ApolloMail — é o que mantém
os três logins com a mesma identidade.

## Marca Apollo

Os demais ativos em `brand/` (ícone, lockups, favicons) são marca da Apollo Solution,
gerados pelo `build-lockups.mjs` do kit — **não** são de uso livre por terceiros.
