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

## ⚠️ Pendente de confirmação — arte de fundo do login

`brand/login/login-bg.webp` e `brand/login/login-panel.webp` (a nebulosa) vieram do kit de
marca da Apollo, via `apollo-mail-webui`. **A procedência não está documentada em lugar
nenhum** — não se sabe se é arte própria, gerada, ou banco de imagens com restrição.

**Enquanto isso não for confirmado, este repositório permanece PRIVADO.** Se a arte for
nossa, basta tornar público; se for licenciada com restrição de redistribuição, trocar os
dois arquivos (só eles) antes de publicar.

## Marca Apollo

Os demais ativos em `brand/` (ícone, lockups, favicons) são marca da Apollo Solution,
gerados pelo `build-lockups.mjs` do kit — **não** são de uso livre por terceiros.
