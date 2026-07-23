#!/usr/bin/env bash
# =============================================================================
# install-codex-plugin.sh
#
# Подключает OpenAI Codex к Claude Code КАК MCP-СЕРВЕР.
#
# ВАЖНО (проверено по докам Claude Code и исходникам Codex, см.
# ../research/codex-plugin-claude-code.md): отдельного «codex-плагина» для
# Claude Code НЕ существует. Штатный способ интеграции — зарегистрировать Codex
# как MCP-сервер. У Codex CLI для этого есть подкоманда `codex mcp-server`
# («Start Codex as an MCP server (stdio)»), а Claude Code добавляет её через
# `claude mcp add <имя> -- <команда>`.
#
# Запуск:
#   bash install-codex-plugin.sh              # зарегистрировать codex как MCP (scope user)
#   bash install-codex-plugin.sh --scope project   # только в текущем проекте (.mcp.json)
#   bash install-codex-plugin.sh --name codex-cli   # другое имя сервера
#   bash install-codex-plugin.sh --remove     # снять регистрацию
#
# Идемпотентен: повторный запуск не плодит дубликаты.
# =============================================================================
set -euo pipefail

NAME="codex"; SCOPE="user"; REMOVE=0
next=""
for a in "$@"; do
  if [ -n "$next" ]; then case "$next" in name) NAME="$a";; scope) SCOPE="$a";; esac; next=""; continue; fi
  case "$a" in
    --name)    next=name ;;
    --name=*)  NAME="${a#--name=}" ;;
    --scope)   next=scope ;;
    --scope=*) SCOPE="${a#--scope=}" ;;
    --remove)  REMOVE=1 ;;
    -h|--help) grep -E '^#( |$)' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "Неизвестный флаг: $a (см. --help)"; exit 2 ;;
  esac
done
case "$SCOPE" in local|user|project) ;; *) echo "--scope: local|user|project"; exit 2 ;; esac

if [ -t 1 ]; then C_G=$'\033[32m'; C_Y=$'\033[33m'; C_R=$'\033[31m'; C_B=$'\033[36m'; C_0=$'\033[0m'
else C_G=; C_Y=; C_R=; C_B=; C_0=; fi
say()  { printf '%s\n' "${C_B}==>${C_0} $*"; }
ok()   { printf '%s\n' "  ${C_G}OK${C_0}   $*"; }
warn() { printf '%s\n' "  ${C_Y}!!${C_0}   $*"; }
die()  { printf '%s\n' "  ${C_R}XX${C_0}   $*" >&2; exit 1; }
have() { command -v "$1" >/dev/null 2>&1; }

# --- предусловия ------------------------------------------------------------
have claude || die "Claude Code не найден. Сначала: bash install-claude-codex.sh --only claude"
have codex  || die "Codex CLI не найден. Сначала: bash install-claude-codex.sh --only codex"
ok "claude: $(claude --version 2>/dev/null | head -1)"
ok "codex:  $(codex --version 2>/dev/null | head -1)"

# codex mcp-server реально существует в этой версии?
if ! codex --help 2>&1 | grep -q 'mcp-server'; then
  warn "в этой версии Codex не видно подкоманды 'mcp-server' — проверь 'codex --help'."
  warn "обнови Codex (bash install-claude-codex.sh --only codex) или сверься с ../research/codex-plugin-claude-code.md"
  die "нет 'codex mcp-server' — регистрировать нечего"
fi

# --- снятие регистрации -----------------------------------------------------
if [ "$REMOVE" = 1 ]; then
  say "Снимаю регистрацию MCP-сервера '$NAME'"
  claude mcp remove "$NAME" -s "$SCOPE" 2>/dev/null && ok "снято" || warn "не был зарегистрирован в scope=$SCOPE"
  exit 0
fi

# --- регистрация (идемпотентно) ---------------------------------------------
say "Регистрирую Codex как MCP-сервер '$NAME' (scope=$SCOPE, транспорт stdio)"
if claude mcp list 2>/dev/null | grep -qE "^${NAME}[[:space:]:]"; then
  ok "'$NAME' уже зарегистрирован — пропускаю (для замены: --remove, затем снова)"
else
  # stdio-сервер: команда = 'codex mcp-server'
  claude mcp add "$NAME" -s "$SCOPE" -- codex mcp-server \
    && ok "добавлено: claude mcp add $NAME -- codex mcp-server" \
    || die "claude mcp add упал — проверь синтаксис 'claude mcp add --help'"
fi

# --- проверка ---------------------------------------------------------------
say "Проверка"
if claude mcp list 2>/dev/null | grep -qE "^${NAME}[[:space:]:]"; then
  ok "'$NAME' в списке MCP-серверов Claude Code"
else
  die "'$NAME' не появился в 'claude mcp list' — проверь вручную"
fi

echo
say "Готово. Но чтобы Codex-MCP реально отвечал:"
warn "Codex должен быть залогинен, иначе mcp-server не сможет обращаться к модели:"
echo "     codex login                                   # ChatGPT OAuth"
echo "     printenv OPENAI_API_KEY | codex login --with-api-key   # или по ключу"
echo
echo "  В сессии Claude Code проверь: /mcp  (или 'claude mcp list'), сервер '$NAME' должен быть Connected."
echo "  Снять: bash $(basename "$0") --remove"
