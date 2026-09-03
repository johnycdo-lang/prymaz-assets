#!/bin/bash
#
# gskills-hook.sh — instala os Google Agent Skills (google/skills) no nível de usuário.
#
# Mesmo molde do ponytail-hook.sh, graphify-hook.sh e uipm-hook.sh publicados aqui:
# `install` copia o script para ~/.claude/ e deixa os skills em ~/.claude/skills/.
#
# O QUE INSTALA, E POR QUE NÃO TUDO: o repositório do Google tem 128 skills, e 110 deles
# são de Google Cloud (GKE, BigQuery, Cloud Run, IAM, Bigtable, Dataproc). Nenhum projeto
# desta conta usa Google Cloud — roda tudo em Vercel + Supabase/Neon. O próprio README do
# Google diz que o instalador é seletivo ("you can select the specific skills to install"),
# então instalar os 128 seria contrariar o desenho do upstream, não segui-lo.
#
# Ficam de fora também os 6 `google-mobile-ads-*` (AdMob para app Android/iOS, que não
# existe aqui) e os 2 `ima-*` (veiculação de anúncio em vídeo).
#
# O que entra são os 7 abaixo — e, entre eles, `finding-google-skills` é o que dá acesso
# aos outros 121: é um roteador de ~12 KB que busca o catálogo remoto e carrega o skill
# certo sob demanda. Foi construído pelo Google exatamente para evitar o pré-carregamento.
#
# USO (Setup script do Environment na web, ou uma vez na máquina no CLI local):
#   gskills-hook.sh install
#
# Nunca quebra a sessão: sem git, sem rede ou com fetch falho, sai 0 avisando.

set -u

CFG="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
GLOBAL="$CFG/gskills-hook.sh"
SELF="$(cd "$(dirname "$0")" 2>/dev/null && pwd)/$(basename "$0")"
DIR="$HOME/.cache/google-skills"
STAMP="$CFG/skills/.gskills-ref"

# Pinado pela mesma razão escrita no ponytail-hook.sh: código de terceiro que carrega em
# toda sessão não deve mudar sozinho. O google/skills NÃO publica tags — só branches —
# então o pin é o SHA do commit. Para atualizar: troque o SHA, confira o diff, e dê push.
# Upstream: github.com/google/skills, Apache-2.0.
#
# ATENÇÃO — este pin NÃO alcança o que o `finding-google-skills` busca em runtime: ele lê
# index.json da `main` e baixa o skill escolhido na hora. Pinar a instalação não pina o
# que o roteador puxa depois. Quem não quiser essa porta aberta, tire-o da lista abaixo.
REF="f234cfba096987f3dee291ce6e7c80b048fb20b3"

# Lista explícita em vez de "tudo menos": auditável, e um skill novo no upstream não entra
# sozinho num container novo.
WANT="developers/finding-google-skills
developers/retrieving-developer-knowledge
analytics/google-analytics-admin-api-basics
analytics/google-analytics-data-api-basics
ads/google-ads-api-quickstart
ads/google-ads-api-account-diagnostics
ads/google-ads-api-mcp-setup"

[ "${1:-}" = install ] || { echo "uso: gskills-hook.sh install"; exit 0; }

command -v git >/dev/null 2>&1 || { echo "[gskills] git não encontrado — abortado."; exit 0; }
mkdir -p "$CFG/skills" || exit 0
[ "$SELF" = "$GLOBAL" ] || cp "$SELF" "$GLOBAL" 2>/dev/null && chmod +x "$GLOBAL" 2>/dev/null

if [ "$(cat "$STAMP" 2>/dev/null)" = "$REF" ] && [ -d "$CFG/skills/finding-google-skills" ]; then
  echo "[gskills] skills já em ${REF:0:7}. ✓"
  exit 0
fi

# Sem tag para clonar, o jeito é buscar o SHA exato. O GitHub permite fetch de commit
# avulso, então isto continua sendo um download raso — não o histórico inteiro.
rm -rf "$DIR"
mkdir -p "$DIR" || exit 0
(
  cd "$DIR" || exit 1
  git init --quiet
  git remote add origin https://github.com/google/skills.git
  git fetch --depth 1 --quiet origin "$REF"
  git checkout --quiet FETCH_HEAD
) >/dev/null 2>&1 || true

if [ ! -d "$DIR/skills" ]; then
  echo "[gskills] fetch de ${REF:0:7} falhou (rede/GitHub?) — a sessão segue SEM os skills."
  exit 0
fi

n=0
for path in $WANT; do
  src="$DIR/skills/$path"
  name=$(basename "$path")
  if [ ! -f "$src/SKILL.md" ]; then
    echo "[gskills] '$path' não existe em ${REF:0:7} — o upstream mudou de lugar. Pulado."
    continue
  fi
  # Substitui por completo: um cp por cima deixaria arquivo órfão da versão anterior
  # convivendo com a nova, e o skill lê o diretório inteiro.
  rm -rf "$CFG/skills/$name"
  cp -r "$src" "$CFG/skills/$name" || continue
  n=$((n + 1))
done

echo "$REF" > "$STAMP"
echo "[gskills] $n skills instalados em $CFG/skills (${REF:0:7})."
