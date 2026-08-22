#!/bin/bash
#
# graphify-hook.sh — engata o graphify em QUALQUER projeto e QUALQUER sessão.
#
# Mesmo molde do `ponytail-hook.sh` publicado neste repositório: um script só, com
# uma ação `install` que copia a SI MESMO para `~/.claude/` e registra os hooks em
# `~/.claude/settings.json` — o nível que o Claude Code lê em todo projeto.
#
# POR QUE ASSIM: na web o `~/.claude` é efêmero e o único gancho por conta é o
# **Setup script** do Environment. E o dono opera pelo celular: colar o script inteiro
# a cada ajuste não se sustenta. Com a cópia publicada aqui, o Setup script é um curl
# fixo e atualizar vira um push neste repositório.
#
# USO (Setup script do Environment, ou uma vez na máquina no CLI local):
#   graphify-hook.sh install    → instala o CLI e registra os hooks no nível de usuário
#   graphify-hook.sh session    → SessionStart: constrói o grafo do repositório da sessão
#
# O QUE CADA PARTE RESOLVE:
#   • CLI  — pacote Python que não vem no container. Instalado com o extra [sql], sem o
#            qual arquivos .sql (migrations) ficam fora do grafo.
#   • hooks PreToolUse — empurram a consulta ao grafo antes da leitura crua de arquivo.
#   • SessionStart — `graphify-out/` é gerado e não versionado, e toda sessão começa de
#            um clone novo, então o grafo precisa ser reconstruído. Só AST, sem LLM.
#
# Nunca quebra a sessão: sem uv, sem python3, sem rede ou com falha na extração, sai 0.

set -u

CFG="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
GLOBAL="$CFG/graphify-hook.sh"
SELF="$(cd "$(dirname "$0")" 2>/dev/null && pwd)/$(basename "$0")"
ACTION="${1:-}"

export PATH="$HOME/.local/bin:$PATH"

# ---------------------------------------------------------------------------
# install — instala o CLI e registra os hooks de usuário.
# ---------------------------------------------------------------------------
if [ "$ACTION" = install ]; then
  mkdir -p "$CFG" || exit 1
  [ "$SELF" = "$GLOBAL" ] || cp "$SELF" "$GLOBAL" || exit 1
  chmod +x "$GLOBAL"

  if ! command -v graphify >/dev/null 2>&1; then
    if command -v uv >/dev/null 2>&1; then
      echo "[graphify] instalando o CLI (graphifyy[sql])…"
      uv tool install --quiet "graphifyy[sql]" \
        || echo "[graphify] falha ao instalar o CLI; os hooks ficam inertes."
    else
      echo "[graphify] uv não encontrado — CLI não instalado; os hooks ficam inertes."
    fi
  fi

  # O merge preserva o resto do settings.json — inclusive os hooks do ponytail — e é
  # idempotente: remove qualquer entrada anterior deste script antes de reinserir.
  command -v python3 >/dev/null 2>&1 || {
    echo "[graphify] python3 não encontrado — hooks não registrados."; exit 0; }

  SETTINGS="$CFG/settings.json" DEST="$GLOBAL" python3 <<'PY' || {
import json, os, sys

path, dest = os.environ["SETTINGS"], os.environ["DEST"]
try:
    with open(path) as fh:
        data = json.load(fh)
except FileNotFoundError:
    data = {}
except (json.JSONDecodeError, OSError) as exc:
    # settings.json ilegível é do usuário: avisar e sair, nunca sobrescrever.
    sys.exit(f"[graphify] {path} ilegível ({exc}) — hooks não registrados.")

hooks = data.setdefault("hooks", {})

def mine(block):
    return any(
        "graphify-hook.sh" in str(h.get("command", ""))
        or "graphify hook-guard" in str(h.get("command", ""))
        for h in block.get("hooks", [])
    )

# A limpeza acontece UMA vez por evento, antes de inserir qualquer entrada nova.
# Filtrar dentro do `put` apagaria a entrada que o `put` anterior acabou de pôr —
# foi exatamente o que aconteceu no primeiro teste: dos dois PreToolUse, sobrou um.
for _event in ("SessionStart", "PreToolUse"):
    hooks[_event] = [b for b in hooks.get(_event, []) if not mine(b)]

def put(event, matcher, command, timeout, status):
    entry = {"hooks": [{"type": "command", "command": command,
                        "timeout": timeout, "statusMessage": status}]}
    if matcher:
        entry["matcher"] = matcher
    hooks.setdefault(event, []).append(entry)

# O grafo é per-repo e o clone é novo a cada sessão, então reconstruir no start.
put("SessionStart", "startup|resume", f'"{dest}" session', 300,
    "Construindo o grafo do código...")

# `command -v` na frente: sem o CLI o hook sai 0 calado, em vez de 127 a cada
# chamada de ferramenta. Caminho absoluto aqui seria armadilha — muda de máquina.
for matcher, mode in (("Bash|Grep", "search"), ("Read|Glob", "read")):
    put("PreToolUse", matcher,
        f"command -v graphify >/dev/null 2>&1 && graphify hook-guard {mode} || true",
        10, "graphify")

with open(path, "w") as fh:
    json.dump(data, fh, indent=2)
    fh.write("\n")
PY
    exit 0
  }

  echo "[graphify] instalado para QUALQUER projeto: $GLOBAL + hooks em $CFG/settings.json"
  exit 0
fi

# ---------------------------------------------------------------------------
# session — constrói o grafo do repositório da sessão.
# ---------------------------------------------------------------------------
if [ "$ACTION" = session ]; then
  command -v graphify >/dev/null 2>&1 || exit 0

  ROOT="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null)}"
  [ -n "$ROOT" ] || exit 0

  # `graphify-out/` não deve sujar o `git status`. O `.git/info/exclude` é local e não
  # versionado, então resolve sem obrigar cada repositório a mexer no `.gitignore`.
  EXCLUDE="$ROOT/.git/info/exclude"
  if [ -f "$EXCLUDE" ] && ! grep -qxF "graphify-out/" "$EXCLUDE" 2>/dev/null; then
    echo "graphify-out/" >>"$EXCLUDE"
  fi

  if [ ! -f "$ROOT/graphify-out/graph.json" ]; then
    echo "[graphify] construindo o grafo do código (só AST, sem LLM)…"
    # O timeout existe para que um repositório grande não segure o início da sessão.
    ( cd "$ROOT" && timeout 300 graphify update . >/dev/null 2>&1 ) \
      || echo "[graphify] grafo não construído; rode 'graphify update .' quando precisar."
  fi
  exit 0
fi

exit 0
