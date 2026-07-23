#!/usr/bin/env bash
# =============================================================================
# install-claude-telegram.sh
#
# Ставит ОФИЦИАЛЬНЫЙ Telegram-плагин для Claude Code
# (telegram@claude-plugins-official). Плагин даёт Claude Code принимать/слать
# сообщения в Telegram, реагировать эмодзи, править сообщения, получать фото,
# показывать «печатает…».
#
# Источник (проверено):
#   https://github.com/anthropics/claude-plugins-official/blob/main/external_plugins/telegram/README.md
#   /plugin install telegram@claude-plugins-official
# Здесь — через CLI (`claude plugin ...`), неинтерактивно.
#
# Предусловие плагина: Bun (MCP-сервер плагина работает на Bun).
#
# Запуск:
#   bash install-claude-telegram.sh            # поставить плагин + Bun
#   bash install-claude-telegram.sh --scope project
#   bash install-claude-telegram.sh --remove
#
# Скрипт НЕ вписывает токен бота (это делаешь ты слэш-командой в сессии).
# =============================================================================
set -euo pipefail

PLUGIN="telegram@claude-plugins-official"
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
  warn "конфиг ~/.claude/channels/telegram/ (в нём токен бота) НЕ трогаю — удали вручную при необходимости"
  exit 0
fi

# --- Bun (предусловие плагина) ----------------------------------------------
if have bun; then ok "bun: $(bun --version 2>/dev/null)"
else
  warn "Bun не найден — MCP-серверу плагина нужен Bun. Ставлю (bun.sh) в ~/.bun"
  if have curl; then curl -fsSL https://bun.sh/install | bash
  elif have wget; then wget -qO- https://bun.sh/install | bash
  else die "нужен curl или wget, чтобы поставить Bun"; fi
  export PATH="$HOME/.bun/bin:$PATH"
  have bun && ok "bun: $(bun --version 2>/dev/null)" || warn "bun не в PATH — добавь ~/.bun/bin в PATH и перезапусти"
fi

# --- маркетплейс claude-plugins-official (обычно уже подключён) -------------
if ! claude plugin marketplace list 2>/dev/null | grep -q 'claude-plugins-official'; then
  say "Подключаю официальный маркетплейс"
  claude plugin marketplace add anthropics/claude-plugins-official && ok "маркетплейс добавлен" \
    || die "не смог подключить claude-plugins-official"
else
  ok "маркетплейс claude-plugins-official уже подключён"
fi

# --- install (идемпотентно) -------------------------------------------------
say "Ставлю плагин $PLUGIN (scope=$SCOPE)"
if claude plugin list 2>/dev/null | grep -qi 'telegram'; then
  ok "telegram-плагин уже установлен — пропускаю (обновить: claude plugin update $PLUGIN)"
else
  claude plugin install "$PLUGIN" -s "$SCOPE" && ok "плагин установлен" || die "claude plugin install упал"
fi

claude plugin list 2>/dev/null | grep -qi 'telegram' && ok "telegram-плагин в списке установленных" \
  || die "плагин не появился в 'claude plugin list'"

# --- итог + безопасность ----------------------------------------------------
echo
say "Готово. Дальше — в сессии Claude Code (токен вписываешь ТЫ, не скрипт):"
echo "  1. /reload-plugins"
echo "  2. Заведи бота у @BotFather (/newbot) → получишь токен."
echo "  3. /telegram:configure <ТОКЕН>       # пишет ~/.claude/channels/telegram/.env"
echo "  4. Запусти с каналом:  claude --channels plugin:$PLUGIN"
echo "  5. Напиши боту в Telegram → получишь 6-значный код → /telegram:access pair <код>"
echo "  6. 🔒 Закрой доступ:  /telegram:access policy allowlist   (по числовым user_id от @userinfobot)"
echo
warn "БЕЗОПАСНОСТЬ: бот получает доступ к Claude Code на этом сервере."
echo "     • По умолчанию политика 'pairing' — сразу переводи в 'allowlist', иначе посторонний,"
echo "       написавший боту, получит код сопряжения."
echo "     • Токен бота — это пароль: не в git/чат/логи. Утёк → /revoke у @BotFather."
echo
echo "  Документация плагина: https://github.com/anthropics/claude-plugins-official/tree/main/external_plugins/telegram"
echo "  Разбор и альтернативы: ../research/telegram-claude-code.md"
