#!/usr/bin/env bash
# =============================================================================
# install-codex-plugin.sh
#
# Ставит ОФИЦИАЛЬНЫЙ плагин OpenAI Codex для Claude Code (openai/codex-plugin-cc).
# Плагин добавляет в Claude Code слэш-команды Codex: /codex:review,
# /codex:adversarial-review, /codex:rescue, /codex:status|result|cancel — code
# review и делегирование задач Codex, не выходя из Claude Code.
#
# Источник (проверено): https://github.com/openai/codex-plugin-cc
#   /plugin marketplace add openai/codex-plugin-cc
#   /plugin install codex@openai-codex
# Здесь то же самое, но через CLI (`claude plugin ...`), неинтерактивно.
#
# Предусловия плагина: Node.js 18.18+, установленный и залогиненный Codex CLI,
# подписка ChatGPT (в т.ч. Free) ИЛИ ключ OpenAI.
#
# Запуск:
#   bash install-codex-plugin.sh                # marketplace add + install
#   bash install-codex-plugin.sh --scope project
#   bash install-codex-plugin.sh --remove
# Идемпотентно.
# =============================================================================
set -euo pipefail

MARKET_SRC="openai/codex-plugin-cc"
MARKET_NAME="openai-codex"
PLUGIN="codex@openai-codex"
SCOPE="user"; REMOVE=0
next=""
for a in "$@"; do
  if [ -n "$next" ]; then case "$next" in scope) SCOPE="$a";; esac; next=""; continue; fi
  case "$a" in
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

have claude || die "Claude Code не найден. Сначала: bash install-claude-codex.sh --only claude"
ok "claude: $(claude --version 2>/dev/null | head -1)"

# --- remove -----------------------------------------------------------------
if [ "$REMOVE" = 1 ]; then
  say "Удаляю плагин $PLUGIN"
  claude plugin uninstall "$PLUGIN" 2>/dev/null && ok "плагин снят" || warn "плагин не был установлен"
  claude plugin marketplace remove "$MARKET_NAME" 2>/dev/null && ok "маркетплейс отключён" || true
  exit 0
fi

# --- предусловия плагина (предупреждаем, не блокируем) ----------------------
if have codex; then ok "codex: $(codex --version 2>/dev/null | head -1)"
else warn "Codex CLI не найден. Плагин может доустановить его сам (/codex:setup), либо: bash install-claude-codex.sh --only codex"; fi
if have node; then
  nv="$(node -v 2>/dev/null | sed 's/^v//; s/\..*//')"
  [ "${nv:-0}" -ge 18 ] 2>/dev/null && ok "node: $(node -v)" || warn "Node < 18.18 — плагину нужен 18.18+"
else warn "Node не найден — плагину нужен Node 18.18+"; fi

# --- marketplace add (идемпотентно) -----------------------------------------
say "Подключаю маркетплейс $MARKET_SRC"
if claude plugin marketplace list 2>/dev/null | grep -q "$MARKET_NAME"; then
  ok "маркетплейс уже подключён"
else
  claude plugin marketplace add "$MARKET_SRC" && ok "маркетплейс добавлен" \
    || die "claude plugin marketplace add упал (проверь: claude plugin marketplace --help)"
fi

# --- install (идемпотентно) -------------------------------------------------
say "Ставлю плагин $PLUGIN (scope=$SCOPE)"
if claude plugin list 2>/dev/null | grep -qi 'codex'; then
  ok "плагин codex уже установлен — пропускаю (обновить: claude plugin update $PLUGIN)"
else
  claude plugin install "$PLUGIN" -s "$SCOPE" && ok "плагин установлен" \
    || die "claude plugin install упал"
fi

# --- проверка ---------------------------------------------------------------
say "Проверка"
claude plugin list 2>/dev/null | grep -qi 'codex' && ok "codex-плагин в списке установленных" \
  || die "плагин не появился в 'claude plugin list'"

echo
say "Готово. Дальше — в сессии Claude Code:"
echo "  1. /reload-plugins            # подхватить плагин (или перезапусти claude)"
echo "  2. /codex:setup               # проверка/доустановка Codex; при необходимости: !codex login"
echo "  3. Команды: /codex:review · /codex:adversarial-review · /codex:rescue · /codex:status"
echo
warn "Codex должен быть ЗАЛОГИНЕН (codex login или ключ), иначе команды плагина не отработают."
echo "  Конфиг модели Codex: ~/.codex/config.toml (или .codex/config.toml в проекте)."
echo "  Снять: bash $(basename "$0") --remove"
