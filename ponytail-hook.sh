#!/bin/bash
#
# ponytail-hook.sh — engata o plugin ponytail nas sessões (idempotente, não-bloqueante).
#
# POR QUE EXISTE: o `.claude/settings.json` declara `ponytail@ponytail` em `enabledPlugins`,
# mas o Claude Code na web sobe o container com `~/.claude/plugins` VAZIO — ele não instala
# plugins de marketplace declarados pelo repo. Verificado em 22/08/2026: `installed_plugins.json`
# vazio, nenhum arquivo do plugin no disco, nenhuma regra injetada. Ou seja, desde 20/08 o
# CLAUDE.md prometia uma regra que as sessões da web nunca receberam — e o silêncio era total,
# porque um plugin que não instala não reclama.
#
# O plugin é só JS sobre builtins do node (sem dependências), e o que ele faz são três hooks.
# Então o caminho mais curto que funciona é chamar esses hooks direto, de um clone em cache,
# em vez de esperar o sistema de plugins.
#
# USO (a partir do .claude/settings.json):
#   ponytail-hook.sh activate   → SessionStart      (garante o clone; emite a regra)
#   ponytail-hook.sh subagent   → SubagentStart     (emite a regra em CADA subagente da Norte)
#   ponytail-hook.sh tracker    → UserPromptSubmit  (processa /ponytail lite|full|ultra|off)
#
# USO GLOBAL (qualquer projeto, qualquer sessão) — ver ponytail-setup.md, Opção C:
#   ponytail-hook.sh install    → copia ESTE arquivo para ~/.claude/ e registra os três hooks
#                                 em ~/.claude/settings.json. Roda uma vez por máquina (CLI
#                                 local) ou a cada container (Setup script do Environment).
#
# Nunca quebra a sessão: sem node, sem rede ou sem clone, sai 0 em silêncio.
# Detalhes e as opções de instalação em paperclip-company/ponytail-setup.md.

set -u

CFG="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
GLOBAL="$CFG/ponytail-hook.sh"
SELF="$(cd "$(dirname "$0")" 2>/dev/null && pwd)/$(basename "$0")"

ACTION="${1:-}"

# ---------------------------------------------------------------------------
# install — a instalação global. Precisa vir ANTES das guardas abaixo, que
# existem para o caminho de execução normal.
# ---------------------------------------------------------------------------
if [ "$ACTION" = install ]; then
  command -v node >/dev/null 2>&1 || {
    echo "[ponytail] install: node não encontrado — abortado (o plugin é JS)."; exit 1; }
  mkdir -p "$CFG" || exit 1
  [ "$SELF" = "$GLOBAL" ] || cp "$SELF" "$GLOBAL" || exit 1
  chmod +x "$GLOBAL"

  # O merge preserva o resto do settings.json e é idempotente: remove qualquer
  # entrada anterior que aponte para este script antes de reinserir os três hooks.
  SETTINGS="$CFG/settings.json" DEST="$GLOBAL" node <<'NODE' || exit 1
const fs = require('fs');
const f = process.env.SETTINGS, sh = process.env.DEST;
let s = {};
try { s = JSON.parse(fs.readFileSync(f, 'utf8')); } catch (e) {}
s.hooks = s.hooks || {};
const put = (evt, matcher, arg, timeout) => {
  const kept = (s.hooks[evt] || []).filter(
    b => !(b.hooks || []).some(h => String(h.command || '').includes('ponytail-hook.sh')));
  const entry = {
    hooks: [{ type: 'command', command: `"${sh}" ${arg}`, timeout,
              statusMessage: 'Carregando o ponytail...' }],
  };
  if (matcher) entry.matcher = matcher;
  s.hooks[evt] = kept.concat([entry]);
};
put('SessionStart', 'startup|resume|clear|compact', 'activate', 15);
put('SubagentStart', null, 'subagent', 5);
put('UserPromptSubmit', null, 'tracker', 5);
fs.writeFileSync(f, JSON.stringify(s, null, 2) + '\n');
NODE

  # Aquece o clone agora: numa sessão nova o SessionStart já encontra tudo pronto.
  "$GLOBAL" activate >/dev/null 2>&1 || true

  echo "[ponytail] instalado para QUALQUER projeto: $GLOBAL + 3 hooks em $CFG/settings.json"
  exit 0
fi

# Com a instalação global no lugar, ela já engata os três hooks em qualquer projeto —
# inclusive neste. Uma cópia de repo rodando junto injetaria a MESMA regra duas vezes
# (~5 KB a mais por sessão e por subagente). A global vence; a cópia do repo se cala.
if [ -f "$GLOBAL" ] && [ "$SELF" != "$GLOBAL" ]; then
  exit 0
fi

# Numa sessão de CLI local o plugin instala de verdade e registra ESTES MESMOS três hooks.
# Sem esta saída, a regra entraria duas vezes (dois blocos de ~5 KB por sessão e por subagente).
# O registro do CLI é a fonte da verdade sobre "instalado"; na web ele fica vazio.
# Se o formato do registro mudar, o pior caso é a regra duplicada — não é quebra.
REG="$CFG/plugins/installed_plugins.json"
grep -q '"ponytail' "$REG" 2>/dev/null && exit 0

DIR="$HOME/.cache/ponytail-plugin"
# Pinado de propósito: código de terceiro que roda em toda sessão não deve mudar sozinho.
# Para atualizar, troque a tag aqui (upstream: DietrichGebert/ponytail, MIT).
REF="v4.9.0"

case "$ACTION" in
  activate) SCRIPT="ponytail-activate.js" ;;
  subagent) SCRIPT="ponytail-subagent.js" ;;
  tracker)  SCRIPT="ponytail-mode-tracker.js" ;;
  *) exit 0 ;;
esac

if [ "$ACTION" = activate ]; then
  # O cache pode ter vindo de outra cópia deste script (a global, ou um Setup script do
  # Environment), que repete a tag FORA do git deste repo. Aceitar qualquer clone que exista
  # rodaria, em silêncio, uma versão que ninguém revisou aqui, com o log jurando ser a $REF.
  # Conferir a tag custa ~10ms e faz o cache velho se corrigir sozinho no próximo start.
  CACHED=$(git -C "$DIR" describe --tags --exact-match 2>/dev/null || true)
  if [ -f "$DIR/hooks/$SCRIPT" ] && [ "$CACHED" = "$REF" ]; then
    echo "[ponytail] plugin em cache ($REF). ✓"
  else
    if [ -n "$CACHED" ] && [ "$CACHED" != "$REF" ]; then
      echo "[ponytail] cache está em $CACHED e este script pede $REF — descartando e re-clonando. Alinhe a tag nas outras cópias (ver ponytail-setup.md)."
    fi
    rm -rf "$DIR"
    git clone --depth 1 --branch "$REF" --quiet \
      https://github.com/DietrichGebert/ponytail.git "$DIR" >/dev/null 2>&1 || true
    if [ -f "$DIR/hooks/$SCRIPT" ]; then
      echo "[ponytail] plugin ausente no start — clonado agora pelo hook ($REF)."
    else
      echo "[ponytail] clone falhou (rede/GitHub?) — a sessão segue SEM a regra do ponytail."
      exit 0
    fi
  fi
  # O plugin pede a configuração de uma statusline UMA vez por máquina e grava um flag para
  # não repetir. Container efêmero = flag novo a cada sessão, então o pedido viria SEMPRE —
  # e sessão da web não tem statusline para configurar. Criamos o flag na frente.
  mkdir -p "$CFG" 2>/dev/null && : > "$CFG/.ponytail-statusline-nudged" 2>/dev/null || true
fi

# subagent/tracker rodam depois do SessionStart na mesma sessão: se o arquivo não está lá,
# o clone falhou e insistir a cada prompt/subagente só somaria latência.
[ -f "$DIR/hooks/$SCRIPT" ] || exit 0
command -v node >/dev/null 2>&1 || exit 0

exec node "$DIR/hooks/$SCRIPT"
