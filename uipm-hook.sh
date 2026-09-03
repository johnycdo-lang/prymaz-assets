#!/bin/bash
#
# uipm-hook.sh — instala os skills do UI/UX Pro Max em QUALQUER projeto e QUALQUER sessão.
#
# Mesmo molde do `ponytail-hook.sh` e do `graphify-hook.sh` publicados aqui: um script só,
# com uma ação `install` que copia a SI MESMO para `~/.claude/` e deixa os skills em
# `~/.claude/skills/` — o nível que o Claude Code lê em todo projeto.
#
# POR QUE EXISTE: em 02/09/2026 os 7 skills foram commitados dentro dos 7 repositórios da
# conta. São 11 MB e 258 arquivos por repo — ~77 MB de blob permanente no git, em repos que
# em três casos não têm interface nenhuma. E atualizar exigiria repetir a operação sete
# vezes. Aqui a instalação fica num lugar só e atualizar é trocar a linha REF abaixo.
#
# USO (Setup script do Environment na web, ou uma vez na máquina no CLI local):
#   uipm-hook.sh install    → clona a tag pinada e instala os skills no nível de usuário
#
# NÃO registra hook nenhum: skill é arquivo, não é gancho. O Claude Code lê
# `~/.claude/skills/` sozinho no início da sessão. Um SessionStart aqui só somaria latência.
#
# Nunca quebra a sessão: sem git, sem rede ou com clone falho, sai 0 avisando.

set -u

CFG="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
GLOBAL="$CFG/uipm-hook.sh"
SELF="$(cd "$(dirname "$0")" 2>/dev/null && pwd)/$(basename "$0")"
DIR="$HOME/.cache/uipm-skill"
STAMP="$CFG/skills/.uipm-ref"

# Pinado de propósito, pela mesma razão escrita no ponytail-hook.sh: código de terceiro que
# carrega em toda sessão não deve mudar sozinho. São 37 scripts Python, e os de design/ e
# design-system/ acessam a rede (urllib.request, API do Gemini, Pexels) — o README do
# upstream afirma que nada disso existe, o que só vale para o skill ui-ux-pro-max.
# Para atualizar: troque a tag, confira o diff do upstream, e dê push neste repositório.
# Upstream: nextlevelbuilder/ui-ux-pro-max-skill, MIT.
REF="v2.15.0"

# `design` fica de fora de propósito: o nome COLIDE com o skill `design` nativo do Claude
# Design (o editor de canvas multi-artboard) e o sombreia — num install global isso valeria
# em todos os projetos, para sempre. É também o skill que chama a API do Gemini. Para
# reativar, esvazie esta lista e aceite a troca conscientemente.
SKIP="design"

[ "${1:-}" = install ] || { echo "uso: uipm-hook.sh install"; exit 0; }

command -v git >/dev/null 2>&1 || { echo "[uipm] git não encontrado — abortado."; exit 0; }
mkdir -p "$CFG/skills" || exit 0
[ "$SELF" = "$GLOBAL" ] || cp "$SELF" "$GLOBAL" 2>/dev/null && chmod +x "$GLOBAL" 2>/dev/null

# O stamp evita re-clonar a cada container quando nada mudou, e faz uma instalação de tag
# antiga se corrigir sozinha no próximo start — mesma lógica do `git describe` do ponytail.
if [ "$(cat "$STAMP" 2>/dev/null)" = "$REF" ] && [ -d "$CFG/skills/ui-ux-pro-max" ]; then
  echo "[uipm] skills já em $REF. ✓"
  exit 0
fi

rm -rf "$DIR"
git clone --depth 1 --branch "$REF" --quiet \
  https://github.com/nextlevelbuilder/ui-ux-pro-max-skill.git "$DIR" >/dev/null 2>&1 || true

if [ ! -d "$DIR/.claude/skills" ]; then
  echo "[uipm] clone de $REF falhou (rede/GitHub?) — a sessão segue SEM os skills."
  exit 0
fi

n=0
for src in "$DIR"/.claude/skills/*/; do
  name=$(basename "$src")
  case " $SKIP " in *" $name "*) continue ;; esac
  # Substitui a versão anterior por completo: um `cp` por cima deixaria arquivo órfão de
  # uma versão passada convivendo com a nova, e o skill lê o diretório inteiro.
  rm -rf "$CFG/skills/$name"
  cp -r "$src" "$CFG/skills/$name" || continue
  n=$((n + 1))
done

echo "$REF" > "$STAMP"
echo "[uipm] $n skills instalados em $CFG/skills ($REF)."
