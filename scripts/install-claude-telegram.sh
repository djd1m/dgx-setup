#!/usr/bin/env bash
# =============================================================================
# install-claude-telegram.sh
#
# Ставит МОСТ Telegram <-> Claude Code: пишешь боту в Telegram, он гоняет
# Claude Code на этом сервере и возвращает ответы.
#
# 🚨 ОФИЦИАЛЬНОГО Telegram-плагина для Claude Code НЕ существует (проверено по
# докам Claude Code, см. ../research/telegram-claude-code.md). Этот скрипт ставит
# самый зрелый community-мост: RichardAtCT/claude-code-telegram (Python, Agent
# SDK, встроенный allowlist + песочница каталога). Это НЕОФИЦИАЛЬНЫЙ проект.
#
# 🔒 БЕЗОПАСНОСТЬ — прочитай до запуска:
#   Бот с доступом к Claude Code = фактически удалённый shell на сервере.
#   - allowlist по ЧИСЛОВОМУ user_id обязателен (username можно подделать);
#   - НЕ использовать --dangerously-skip-permissions;
#   - запускать от отдельного непривилегированного пользователя;
#   - APPROVED_DIRECTORY ограничивает, куда бот имеет доступ;
#   - токен бота и ключи — только в .env (chmod 600), не в git/чат/логи.
#
# Запуск:
#   bash install-claude-telegram.sh            # склонировать + подготовить конфиг
#   bash install-claude-telegram.sh --dir /opt/cctg   # каталог установки
#   bash install-claude-telegram.sh --ref v1.6.0      # версия моста (тег)
#   bash install-claude-telegram.sh --remove   # удалить установку
#
# Скрипт НЕ запускает бота и НЕ вписывает секреты — только готовит окружение.
# =============================================================================
set -euo pipefail

REPO_URL="https://github.com/RichardAtCT/claude-code-telegram"
BRIDGE_REF="v1.6.0"          # проверенный тег на момент написания; переопредели --ref
DIR="$HOME/claude-code-telegram"
REMOVE=0
next=""
for a in "$@"; do
  if [ -n "$next" ]; then case "$next" in dir) DIR="$a";; ref) BRIDGE_REF="$a";; esac; next=""; continue; fi
  case "$a" in
    --dir)    next=dir ;;
    --dir=*)  DIR="${a#--dir=}" ;;
    --ref)    next=ref ;;
    --ref=*)  BRIDGE_REF="${a#--ref=}" ;;
    --remove) REMOVE=1 ;;
    -h|--help) grep -E '^#( |$)' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "Неизвестный флаг: $a (см. --help)"; exit 2 ;;
  esac
done

if [ -t 1 ]; then C_G=$'\033[32m'; C_Y=$'\033[33m'; C_R=$'\033[31m'; C_B=$'\033[36m'; C_0=$'\033[0m'
else C_G=; C_Y=; C_R=; C_B=; C_0=; fi
say()  { printf '%s\n' "${C_B}==>${C_0} $*"; }
ok()   { printf '%s\n' "  ${C_G}OK${C_0}   $*"; }
warn() { printf '%s\n' "  ${C_Y}!!${C_0}   $*"; }
die()  { printf '%s\n' "  ${C_R}XX${C_0}   $*" >&2; exit 1; }
have() { command -v "$1" >/dev/null 2>&1; }

# --- remove -----------------------------------------------------------------
if [ "$REMOVE" = 1 ]; then
  say "Удаляю установку моста"
  have uv && uv tool uninstall claude-code-telegram 2>/dev/null || true
  if [ -d "$DIR" ]; then
    warn "каталог $DIR (в нём может быть .env с секретами) НЕ удаляю автоматически."
    warn "удали вручную, когда убедишься, что ничего важного там нет:  rm -rf '$DIR'"
  fi
  ok "готово"
  exit 0
fi

# --- предусловия / автоопределение ------------------------------------------
say "Проверяю окружение"

# root/sudo
if [ "$(id -u)" -eq 0 ]; then SUDO=""; warn "запущено от root — лучше ставить бота под ОТДЕЛЬНЫМ непривилегированным пользователем"
elif have sudo; then SUDO="sudo"; else SUDO=""; fi

# пакетный менеджер (для доустановки git/python при отсутствии)
PM=none
for pm in apt-get dnf yum pacman zypper apk brew; do have "$pm" && { PM="$pm"; break; }; done
pm_install() { case "$PM" in
  apt-get) $SUDO apt-get update -qq && $SUDO apt-get install -y "$@" ;;
  dnf) $SUDO dnf install -y "$@" ;; yum) $SUDO yum install -y "$@" ;;
  pacman) $SUDO pacman -Sy --noconfirm "$@" ;; zypper) $SUDO zypper install -y "$@" ;;
  apk) $SUDO apk add "$@" ;; brew) brew install "$@" ;;
  *) warn "поставь вручную: $*"; return 1 ;;
esac; }

# claude — зависимость
have claude && ok "claude: $(claude --version 2>/dev/null | head -1)" \
  || die "Claude Code не найден. Сначала: bash install-claude-codex.sh --only claude"

# git
have git || { warn "git нет — ставлю"; pm_install git || die "поставь git вручную"; }
ok "git: $(git --version 2>/dev/null)"

# python 3.11+
PY=""
for c in python3.13 python3.12 python3.11 python3; do
  if have "$c"; then
    v="$("$c" -c 'import sys;print(f"{sys.version_info[0]}{sys.version_info[1]:02d}")' 2>/dev/null || echo 0)"
    [ "$v" -ge 311 ] 2>/dev/null && { PY="$c"; break; }
  fi
done
if [ -z "$PY" ]; then
  warn "Python 3.11+ не найден — мосту нужен 3.11+. Пробую доустановить."
  pm_install python3 || true
  have python3 && PY=python3 || die "поставь Python 3.11+ вручную"
fi
ok "python: $("$PY" --version 2>/dev/null)"

# uv (рекомендованный установщик моста) — ставим в user-local, если нет
if ! have uv; then
  warn "uv не найден — ставлю официальным инсталлятором (astral.sh) в ~/.local/bin"
  if have curl; then curl -LsSf https://astral.sh/uv/install.sh | sh
  elif have wget; then wget -qO- https://astral.sh/uv/install.sh | sh
  else die "нужен curl или wget, чтобы поставить uv"; fi
  export PATH="$HOME/.local/bin:$PATH"
fi
have uv && ok "uv: $(uv --version 2>/dev/null)" || warn "uv так и не появился — установка деп. может не пройти"

# --- получить код моста (идемпотентно) --------------------------------------
say "Получаю мост: $REPO_URL @ $BRIDGE_REF"
if [ -d "$DIR/.git" ]; then
  ok "каталог уже есть: $DIR — обновляю до $BRIDGE_REF"
  git -C "$DIR" fetch --tags --quiet || warn "git fetch не прошёл"
  git -C "$DIR" checkout --quiet "$BRIDGE_REF" 2>/dev/null || warn "тег $BRIDGE_REF не найден — оставляю как есть (проверь релизы: $REPO_URL/releases)"
else
  git clone --quiet "$REPO_URL" "$DIR" || die "git clone упал"
  git -C "$DIR" checkout --quiet "$BRIDGE_REF" 2>/dev/null \
    || warn "тег $BRIDGE_REF не найден — на дефолтной ветке. Проверь актуальный релиз: $REPO_URL/releases"
  ok "склонировано в $DIR"
fi

# --- поставить зависимости (best-effort) ------------------------------------
say "Ставлю зависимости моста (make dev)"
if have make && have uv; then
  ( cd "$DIR" && make dev ) && ok "зависимости установлены" \
    || warn "make dev не прошёл — поставь вручную по README: $REPO_URL"
else
  warn "нет make или uv — установи зависимости по инструкции проекта: $REPO_URL"
fi

# --- заготовка .env (плейсхолдеры, БЕЗ секретов, chmod 600) ------------------
say "Готовлю .env (только плейсхолдеры — секреты впишешь сам)"
ENV="$DIR/.env"
if [ -f "$ENV" ]; then
  ok ".env уже существует — не трогаю (chmod 600 на всякий случай)"; chmod 600 "$ENV" || true
elif [ -f "$DIR/.env.example" ]; then
  cp "$DIR/.env.example" "$ENV"; chmod 600 "$ENV"
  ok "создан $ENV из .env.example (chmod 600)"
else
  umask 077
  cat > "$ENV" <<'EOF'
# claude-code-telegram — заполни РЕАЛЬНЫМИ значениями. НЕ коммить, НЕ показывай.
TELEGRAM_BOT_TOKEN=REPLACE_ME_токен_от_BotFather
TELEGRAM_BOT_USERNAME=REPLACE_ME_username_бота
ALLOWED_USERS=REPLACE_ME_числовой_id_от_@userinfobot   # через запятую; ТОЛЬКО свои id
APPROVED_DIRECTORY=REPLACE_ME_/путь/к/рабочей/папке      # куда боту МОЖНО (песочница)
# опционально:
# ANTHROPIC_API_KEY=          # можно не задавать, если Claude Code уже залогинен
# CLAUDE_MAX_COST_PER_USER=5  # лимит расхода на пользователя, USD
EOF
  chmod 600 "$ENV"
  ok "создан $ENV с плейсхолдерами (chmod 600)"
fi

# --- итог + безопасность ----------------------------------------------------
echo
say "Готово — но бот ещё НЕ запущен и секреты НЕ заданы. Дальше ты:"
echo "  1. Заведи бота у @BotFather, узнай свой числовой id у @userinfobot."
echo "  2. Впиши РЕАЛЬНЫЕ значения в:  $ENV"
echo "       TELEGRAM_BOT_TOKEN, TELEGRAM_BOT_USERNAME, ALLOWED_USERS (только свои id!), APPROVED_DIRECTORY"
echo "  3. Запусти:  cd '$DIR' && make run     (или make run-debug для логов)"
echo
warn "БЕЗОПАСНОСТЬ (это неофициальный мост, бот = удалённый доступ к Claude Code):"
echo "     • ALLOWED_USERS — только твои числовые id; всё остальное бот должен отклонять."
echo "     • APPROVED_DIRECTORY — узкая рабочая папка, НЕ '\$HOME' и не '/'."
echo "     • НЕ запускай под root и НЕ используй --dangerously-skip-permissions."
echo "     • Токен бота утёк -> немедленно /revoke у @BotFather."
echo
echo "  Полная документация и все переменные: $REPO_URL"
echo "  Разбор вариантов и рисков:            ../research/telegram-claude-code.md"
