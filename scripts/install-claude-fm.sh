#!/usr/bin/env bash
# =============================================================================
# install-claude-fm.sh
#
# Настраивает Claude Code на работу с Cloud.ru Foundation Models НАПРЯМУЮ через
# их Anthropic-совместимый эндпоинт /v1/messages — БЕЗ LiteLLM, БЕЗ docker, БЕЗ
# туннеля. Создаёт команду `claude-fm` (обёртка), которая запускает Claude Code
# с нужными переменными.
#
# ПРОВЕРЕНО живым запросом к Cloud.ru 2026-07-24: у foundation-models.api.cloud.ru
# ЕСТЬ /v1/messages (Anthropic Messages API). ⚠️ Но в ОФИЦ. ДОКАХ Cloud.ru его НЕТ (только
# OpenAI /v1/chat/completions) — эндпоинт недокументирован, может измениться/исчезнуть.
# Если начнёт отдавать 404 — откат на LiteLLM-путь (см. for-ai/02-claude-code-cloudru.md).
# Работает, например, с моделями
# `deepseek-ai/DeepSeek-V4-Pro` (внутренняя, данные в РФ) и `anthropic/claude-haiku-4.5`
# (внешний настоящий Claude). Это НЕ путь из 02-claude-code-cloudru.md (там LiteLLM,
# т.к. на момент написания /v1/messages ещё не было) — это отдельный, прямой путь.
#
# Запуск:
#   bash install-claude-fm.sh                 # спросит ключ Cloud.ru, настроит claude-fm
#   bash install-claude-fm.sh --model deepseek-ai/DeepSeek-V4-Pro
#   bash install-claude-fm.sh --model anthropic/claude-haiku-4.5   # настоящий Claude (внешний!)
#   bash install-claude-fm.sh --diagnose      # только проверка эндпоинта/моделей, без изменений
#   bash install-claude-fm.sh --remove        # удалить claude-fm и секреты
#
# Ключ Cloud.ru — секрет: хранится в ~/.dgx-claude/cloudru-fm.env (chmod 600),
# в обёртку и в git не попадает.
# =============================================================================
set -euo pipefail

BASE="https://foundation-models.api.cloud.ru"     # Claude Code сам добавит /v1/messages
STATE_DIR="${DGX_CLAUDE_HOME:-$HOME/.dgx-claude}"
SECRETS="$STATE_DIR/cloudru-fm.env"
WRAPPER="$HOME/.local/bin/claude-fm"
# Порядок предпочтения моделей при автоподборе (первая рабочая — по умолчанию):
DEFAULT_MODELS="deepseek-ai/DeepSeek-V4-Pro deepseek-ai/DeepSeek-V3.1-Terminus anthropic/claude-haiku-4.5"

MODEL=""; DIAGNOSE_ONLY=0; REMOVE=0
next=""
for a in "$@"; do
  if [ -n "$next" ]; then case "$next" in model) MODEL="$a";; esac; next=""; continue; fi
  case "$a" in
    --model)    next=model ;;
    --model=*)  MODEL="${a#--model=}" ;;
    --diagnose) DIAGNOSE_ONLY=1 ;;
    --remove)   REMOVE=1 ;;
    -h|--help)  grep -E '^#( |$)' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
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
  say "Удаляю claude-fm"
  rm -f "$WRAPPER" && ok "обёртка удалена: $WRAPPER" || true
  [ -f "$SECRETS" ] && { rm -f "$SECRETS"; ok "секреты удалены: $SECRETS"; }
  exit 0
fi

# --- предусловия ------------------------------------------------------------
have curl || die "нужен curl"
if ! have claude; then
  warn "Claude Code не найден — claude-fm без него бесполезен."
  warn "Поставь: bash install-claude-codex.sh --only claude   (или см. 01/10)"
  [ "$DIAGNOSE_ONLY" = 1 ] || die "нет claude — останавливаюсь"
else
  ok "claude: $(claude --version 2>/dev/null | head -1)"
fi

# --- ключ Cloud.ru ----------------------------------------------------------
mkdir -p "$STATE_DIR"; chmod 700 "$STATE_DIR" 2>/dev/null || true
# приоритет: переменная окружения -> уже сохранённый файл -> спросить
KEY="${CLOUD_RU_FM_API_KEY:-}"
# shellcheck disable=SC1090
[ -z "$KEY" ] && [ -f "$SECRETS" ] && KEY="$(. "$SECRETS" 2>/dev/null; printf '%s' "${CLOUD_RU_FM_API_KEY:-}")"
if [ -z "$KEY" ]; then
  if [ "$DIAGNOSE_ONLY" = 1 ]; then die "нет ключа Cloud.ru (задай CLOUD_RU_FM_API_KEY) — для --diagnose нужен ключ"; fi
  say "Нужен ключ Cloud.ru Foundation Models (личный кабинет → сервисный аккаунт → API-ключ)"
  read -r -s -p "  Вставь ключ Cloud.ru (ввод скрыт): " KEY; echo
  [ -n "$KEY" ] || die "ключ пустой — останавливаюсь"
fi

# --- самодиагностика: сеть + список моделей ---------------------------------
say "Проверяю ключ и сеть до Cloud.ru"
mcode="$(curl -s -o /tmp/fm-models.json -w '%{http_code}' -m 20 "$BASE/v1/models" -H "Authorization: Bearer $KEY" 2>/dev/null || echo 000)"
case "$mcode" in
  200) ok "ключ принят, /v1/models отвечает ($(grep -o '"id"' /tmp/fm-models.json | wc -l | tr -d ' ') моделей)" ;;
  401|403) die "ключ отклонён (HTTP $mcode) — проверь ключ Cloud.ru, не выдумывай новый" ;;
  000) die "нет сети до $BASE — проверь интернет DGX" ;;
  *) warn "неожиданный HTTP $mcode на /v1/models — продолжаю осторожно" ;;
esac

# --- самодиагностика: /v1/messages + подбор рабочей модели ------------------
probe_msg() { # probe_msg <model> -> печатает HTTP-код
  curl -s -o /tmp/fm-msg.json -w '%{http_code}' -m 30 "$BASE/v1/messages" \
    -H "Authorization: Bearer $KEY" -H "anthropic-version: 2023-06-01" -H "content-type: application/json" \
    -d "{\"model\":\"$1\",\"max_tokens\":8,\"messages\":[{\"role\":\"user\",\"content\":\"hi\"}]}" 2>/dev/null || echo 000
}

say "Проверяю Anthropic-эндпоинт /v1/messages и подбираю рабочую модель"
CHOSEN=""
CANDIDATES="$DEFAULT_MODELS"
[ -n "$MODEL" ] && CANDIDATES="$MODEL"     # если задана явно — проверяем только её
for m in $CANDIDATES; do
  code="$(probe_msg "$m")"
  case "$code" in
    200) ok "модель работает: $m (HTTP 200)"; CHOSEN="$m"; break ;;
    403) warn "$m — 403 (не подключена к проекту)"; ;;
    404) warn "$m — 404 (нет такого id/маршрута)"; ;;
    *)   warn "$m — HTTP $code" ;;
  esac
done
[ -z "$CHOSEN" ] && die "ни одна кандидатная модель не ответила на /v1/messages. Проверь, какие модели подключены к твоему проекту Cloud.ru, и задай --model <id>."

# внутренняя (РФ) или внешняя?
case "$CHOSEN" in
  anthropic/*) warn "выбрана ВНЕШНЯЯ модель ($CHOSEN): настоящий Claude, но данные уходят из РФ и это платно дороже." ;;
  *)           ok "выбрана внутренняя модель ($CHOSEN): данные остаются в инфраструктуре Cloud.ru (РФ)." ;;
esac

if [ "$DIAGNOSE_ONLY" = 1 ]; then
  echo; say "только диагностика — ничего не менял. Рабочая модель: $CHOSEN"; exit 0
fi

# --- сохранить секрет + модель ----------------------------------------------
umask 077
cat > "$SECRETS" <<EOF
# Cloud.ru FM — секрет. НЕ коммитить, НЕ показывать. chmod 600.
export CLOUD_RU_FM_API_KEY=$(printf '%q' "$KEY")
export CLAUDE_FM_MODEL=$(printf '%q' "$CHOSEN")
EOF
chmod 600 "$SECRETS"
ok "ключ и модель сохранены: $SECRETS (chmod 600)"

# --- обёртка claude-fm ------------------------------------------------------
mkdir -p "$(dirname "$WRAPPER")"
cat > "$WRAPPER" <<EOF
#!/usr/bin/env bash
# claude-fm — Claude Code через Cloud.ru FM (Anthropic API напрямую). Сгенерировано install-claude-fm.sh.
set -a; . "$SECRETS"; set +a
export ANTHROPIC_BASE_URL="$BASE"
export ANTHROPIC_AUTH_TOKEN="\$CLOUD_RU_FM_API_KEY"   # Cloud.ru ждёт Authorization: Bearer
export ANTHROPIC_MODEL="\${CLAUDE_FM_MODEL:-$CHOSEN}"
unset ANTHROPIC_API_KEY                                # чтобы не слался x-api-key вместо Bearer
exec claude "\$@"
EOF
chmod 755 "$WRAPPER"
ok "создана команда: $WRAPPER"

case ":$PATH:" in *":$HOME/.local/bin:"*) : ;; *)
  warn "$HOME/.local/bin не в PATH — добавь в ~/.bashrc:  export PATH=\"\$HOME/.local/bin:\$PATH\"" ;;
esac

# --- итог --------------------------------------------------------------------
echo
say "Готово. Запуск:  claude-fm    (модель: $CHOSEN)"
echo "  Проверка одним запросом:"
echo "     claude-fm -p 'скажи привет одним словом по-русски'"
echo "  Сменить модель:  bash $(basename "$0") --model <id>   (или правь CLAUDE_FM_MODEL в $SECRETS)"
echo "  Удалить:         bash $(basename "$0") --remove"
warn "Агентный цикл Claude Code требователен к вызову инструментов; на не-Claude модели это может работать хуже."
warn "Проверь смоук-тестом инструментов:  claude-fm -p 'прочитай /etc/hostname и выполни uname -m'"
