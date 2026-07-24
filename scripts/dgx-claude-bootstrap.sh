#!/usr/bin/env bash
# =============================================================================
# dgx-claude-bootstrap.sh
#
# Чистый DGX -> Claude Code, который ходит в модели Anthropic и OpenAI ЧЕРЕЗ
# твой VLESS-прокси (точка выхода не важна), с учётом токенов и денег в LiteLLM.
#
# Цепочка, которую собирает скрипт:
#
#   Claude Code
#     | ANTHROPIC_BASE_URL=http://127.0.0.1:4000   (локально, без прокси)
#   LiteLLM :4000            <- считает модель, токены, стоимость
#     | HTTPS_PROXY=http://127.0.0.1:10809         (свой выход в туннель)
#   xray-клиент :10809       <- транспорт (HTTP inbound -> VLESS)
#     | VLESS
#   твой VPS в КЗ            <- продолжает считать байты, история цела
#     |
#   api.anthropic.com / api.openai.com
#
# Подробности и обоснование: ../for-human/09-proxy-accounting.md  и  10-bootstrap.md
#
# Запуск:
#   bash dgx-claude-bootstrap.sh                 # всё по порядку, с вопросами
#   bash dgx-claude-bootstrap.sh --diagnose      # только диагностика, ничего не ставит
#   bash dgx-claude-bootstrap.sh --yes           # не переспрашивать (для повторных прогонов)
#
# Пропуск фаз — любую можно выключить своим --skip-<фаза>:
#   --skip-diagnose  --skip-xray  --skip-claude  --skip-litellm  --skip-configure  --skip-verify
# Либо выполнить ТОЛЬКО нужные фазы:
#   bash dgx-claude-bootstrap.sh --only claude,litellm        # только эти две
#   bash dgx-claude-bootstrap.sh --only verify                # только сквозная проверка
# Фазы: diagnose, xray, claude, litellm, configure, verify.
#
# ГЕОГРАФИЯ НЕ ПРОВЕРЯЕТСЯ. Точка выхода прокси может меняться и для работы не важна —
# скрипт проверяет лишь, что через туннель есть выход в интернет, а не из какой он страны.
# (Соответствие страновым требованиям сервисов — на ответственности пользователя; см. 09.)
# =============================================================================
set -euo pipefail

# --- пиннинг (проверено на момент написания) --------------------------------
XRAY_VERSION="v26.3.27"
XRAY_ARM64_SHA256="4d30283ae614e3057f730f67cd088a42be6fdf91f8639d82cb69e48cde80413c"
XRAY_AMD64_SHA256="23cd9af937744d97776ee35ecad4972cf4b2109d1e0fe6be9930467608f7c8ae"
LITELLM_IMAGE="ghcr.io/berriai/litellm:v1.92.0"   # есть linux/arm64

# --- пути -------------------------------------------------------------------
STATE_DIR="${DGX_CLAUDE_HOME:-$HOME/.dgx-claude}"
SECRETS="$STATE_DIR/secrets.env"
XRAY_CONF="$STATE_DIR/xray.json"
LITELLM_CONF="$STATE_DIR/litellm.config.yaml"
XRAY_BIN="$HOME/.local/bin/xray"
XRAY_UNIT="$HOME/.config/systemd/user/dgx-xray.service"
HTTP_PORT="${XRAY_HTTP_PORT:-10809}"
SOCKS_PORT="${XRAY_SOCKS_PORT:-10808}"
LITELLM_PORT=4000
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# --- флаги ------------------------------------------------------------------
# Любую фазу можно пропустить своим --skip-<фаза>. Фазы: diagnose, xray, claude,
# litellm, configure, verify. Также --only <фаза[,фаза...]> — выполнить ТОЛЬКО их.
ASSUME_YES=0; DO_DIAGNOSE_ONLY=0
SKIP_DIAGNOSE=0; SKIP_XRAY=0; SKIP_CLAUDE=0; SKIP_LITELLM=0; SKIP_CONFIGURE=0; SKIP_VERIFY=0
ONLY_PHASES=""
next_is_only=0
for a in "$@"; do
  if [ "$next_is_only" = 1 ]; then ONLY_PHASES="$a"; next_is_only=0; continue; fi
  case "$a" in
  --yes|-y)         ASSUME_YES=1 ;;
  --diagnose)       DO_DIAGNOSE_ONLY=1 ;;
  --skip-diagnose)  SKIP_DIAGNOSE=1 ;;
  --skip-xray)      SKIP_XRAY=1 ;;
  --skip-claude)    SKIP_CLAUDE=1 ;;
  --skip-litellm)   SKIP_LITELLM=1 ;;
  --skip-configure) SKIP_CONFIGURE=1 ;;
  --skip-verify)    SKIP_VERIFY=1 ;;
  --only)           next_is_only=1 ;;
  --only=*)         ONLY_PHASES="${a#--only=}" ;;
  -h|--help)        grep -E '^#( |$)' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
  *) echo "Неизвестный флаг: $a (см. --help)"; exit 2 ;;
  esac
done

# --only pre-empts skips: всё, что НЕ перечислено в --only, помечается как skip.
if [ -n "$ONLY_PHASES" ]; then
  SKIP_DIAGNOSE=1; SKIP_XRAY=1; SKIP_CLAUDE=1; SKIP_LITELLM=1; SKIP_CONFIGURE=1; SKIP_VERIFY=1
  IFS=', ' read -r -a _only_arr <<< "$ONLY_PHASES"
  for p in "${_only_arr[@]}"; do case "$p" in
    diagnose)  SKIP_DIAGNOSE=0 ;;
    xray)      SKIP_XRAY=0 ;;
    claude)    SKIP_CLAUDE=0 ;;
    litellm)   SKIP_LITELLM=0 ;;
    configure) SKIP_CONFIGURE=0 ;;
    verify)    SKIP_VERIFY=0 ;;
    "" ) ;;
    *) echo "Неизвестная фаза в --only: $p (diagnose|xray|claude|litellm|configure|verify)"; exit 2 ;;
  esac; done
fi

# --- вывод ------------------------------------------------------------------
if [ -t 1 ]; then C_R=$'\033[31m'; C_G=$'\033[32m'; C_Y=$'\033[33m'; C_B=$'\033[36m'; C_0=$'\033[0m'
else C_R=; C_G=; C_Y=; C_B=; C_0=; fi
say()  { printf '%s\n' "${C_B}==>${C_0} $*"; }
ok()   { printf '%s\n' "  ${C_G}OK${C_0}   $*"; }
warn() { printf '%s\n' "  ${C_Y}WARN${C_0} $*"; }
err()  { printf '%s\n' "  ${C_R}FAIL${C_0} $*" >&2; }
die()  { err "$*"; exit 1; }
ask()  { # ask "вопрос" -> 0 если да
  [ "$ASSUME_YES" = 1 ] && return 0
  local r; read -r -p "  $1 [y/N] " r; [ "$r" = y ] || [ "$r" = Y ]; }

have() { command -v "$1" >/dev/null 2>&1; }

# =============================================================================
# Фаза 0. Диагностика (только читает, ничего не меняет)
# =============================================================================
ARCH=""; XRAY_SHA=""; XRAY_ASSET=""
phase_diagnose() {
  say "Фаза 0 — диагностика"

  ARCH="$(uname -m)"
  case "$ARCH" in
    aarch64|arm64) ok "архитектура $ARCH (DGX Spark / GB10 — как и ожидается)"
                   XRAY_SHA="$XRAY_ARM64_SHA256"; XRAY_ASSET="Xray-linux-arm64-v8a.zip" ;;
    x86_64|amd64)  warn "архитектура $ARCH — не DGX Spark. Скрипт пойдёт, но это не GB10."
                   XRAY_SHA="$XRAY_AMD64_SHA256"; XRAY_ASSET="Xray-linux-64.zip" ;;
    *) die "архитектура $ARCH не поддерживается этим скриптом" ;;
  esac

  if [ -r /etc/os-release ]; then . /etc/os-release; ok "ОС: ${PRETTY_NAME:-неизвестно}"; fi
  local mem; mem="$(free -g 2>/dev/null | awk '/^Mem:/{print $2}')" || mem="?"
  ok "оперативной памяти: ${mem} ГБ"

  # что уже стоит
  have claude  && ok "Claude Code: $(claude --version 2>/dev/null | head -1)" || warn "Claude Code не установлен"
  have docker  && ok "docker: $(docker --version 2>/dev/null)" || warn "docker не установлен (нужен для LiteLLM)"
  if have docker && docker compose version >/dev/null 2>&1; then ok "docker compose доступен"
  else warn "docker compose (v2) не найден"; fi
  [ -x "$XRAY_BIN" ] && ok "xray уже установлен: $XRAY_BIN" || warn "xray-клиент ещё не установлен"

  # свободны ли порты
  local busy=0
  for p in "$HTTP_PORT" "$LITELLM_PORT" 5432; do
    if ss -ltn 2>/dev/null | awk '{print $4}' | grep -qE "[:.]$p\$"; then
      warn "порт $p уже занят — проверь, не остаток ли это прошлого запуска"; busy=1
    fi
  done
  [ "$busy" = 0 ] && ok "порты $HTTP_PORT / $LITELLM_PORT / 5432 свободны"

  # достижимость (для фазы установки, не для рантайма моделей)
  say "  достижимость (нужна на этапе установки; сами модели пойдут через КЗ):"
  for url in https://github.com https://ghcr.io https://downloads.claude.ai; do
    if curl -fsS --max-time 8 -o /dev/null "$url" 2>/dev/null; then ok "$url"
    else warn "$url недоступен отсюда — ставить придётся из открытой сети (см. 10-bootstrap.md)"; fi
  done
}

# =============================================================================
# Секреты
# =============================================================================
init_secrets() {
  mkdir -p "$STATE_DIR"; chmod 700 "$STATE_DIR"
  [ -f "$SECRETS" ] || { : > "$SECRETS"; }
  chmod 600 "$SECRETS"
  set -a
  # shellcheck source=/dev/null
  . "$SECRETS"
  set +a
}
save_secret() { # save_secret KEY VALUE
  local k="$1" v="$2"
  grep -v "^export $k=" "$SECRETS" > "$SECRETS.tmp" 2>/dev/null || true
  printf 'export %s=%q\n' "$k" "$v" >> "$SECRETS.tmp"
  mv "$SECRETS.tmp" "$SECRETS"; chmod 600 "$SECRETS"
  export "$k=$v"
}
gen_key() { openssl rand -hex 24 2>/dev/null || head -c24 /dev/urandom | od -An -tx1 | tr -d ' \n'; }

# =============================================================================
# Фаза 1. xray-клиент (туннель в КЗ)
# =============================================================================
install_xray_binary() {
  [ -x "$XRAY_BIN" ] && { ok "xray уже на месте"; return; }
  say "  ставлю xray $XRAY_VERSION ($XRAY_ASSET)"
  local tmp; tmp="$(mktemp -d)"
  local url="https://github.com/XTLS/Xray-core/releases/download/$XRAY_VERSION/$XRAY_ASSET"
  curl -fL --max-time 120 -o "$tmp/xray.zip" "$url" || die "не смог скачать xray с $url"
  local got; got="$(sha256sum "$tmp/xray.zip" | awk '{print $1}')"
  [ "$got" = "$XRAY_SHA" ] || die "SHA256 xray не совпал! ожидал $XRAY_SHA, получил $got — НЕ ставлю"
  ok "SHA256 xray совпал"
  python3 -m zipfile -e "$tmp/xray.zip" "$tmp/x/"
  mkdir -p "$(dirname "$XRAY_BIN")"
  install -m 0755 "$tmp/x/xray" "$XRAY_BIN"
  rm -rf "$tmp"
  ok "xray установлен: $XRAY_BIN"
}

phase_xray() {
  say "Фаза 1 — туннель в КЗ (xray-клиент)"
  install_xray_binary

  if [ ! -f "$XRAY_CONF" ]; then
    echo
    echo "  Нужна ссылка подключения к твоему VPS в КЗ — строка вида:"
    echo "    vless://<uuid>@<host>:<port>?...#имя"
    echo "  Возьми её в своей панели/клиенте (кнопка «Share»/«Экспорт ссылки»)."
    echo "  Это СЕКРЕТ: в консоли не отобразится, сохранится только локально (chmod 600),"
    echo "  в репозиторий и в чат не попадёт."
    echo
    local link
    read -r -s -p "  Вставь vless:// ссылку: " link; echo
    [ -n "$link" ] || die "пустая ссылка"
    XRAY_HTTP_PORT="$HTTP_PORT" XRAY_SOCKS_PORT="$SOCKS_PORT" \
      python3 "$SCRIPT_DIR/vless2xray.py" "$link" > "$XRAY_CONF" || die "не разобрал ссылку"
    chmod 600 "$XRAY_CONF"
    ok "конфиг xray сгенерирован: $XRAY_CONF (600)"
  else
    ok "конфиг xray уже есть: $XRAY_CONF"
  fi

  "$XRAY_BIN" run -test -c "$XRAY_CONF" >/dev/null 2>&1 \
    || die "xray отверг конфиг — проверь ссылку: $XRAY_BIN run -test -c $XRAY_CONF"
  ok "xray принял конфиг"

  # systemd --user, чтобы туннель жил и после выхода из сессии
  mkdir -p "$(dirname "$XRAY_UNIT")"
  cat > "$XRAY_UNIT" <<UNIT
[Unit]
Description=DGX xray client (VLESS tunnel to KZ)
After=network-online.target
[Service]
ExecStart=$XRAY_BIN run -c $XRAY_CONF
Restart=on-failure
RestartSec=3
[Install]
WantedBy=default.target
UNIT
  if have systemctl && systemctl --user show-environment >/dev/null 2>&1; then
    loginctl enable-linger "$USER" >/dev/null 2>&1 || true
    systemctl --user daemon-reload
    systemctl --user enable --now dgx-xray.service
    ok "xray запущен как systemd --user (dgx-xray.service)"
  else
    warn "systemd --user недоступен — запускаю xray в фоне (nohup)"
    pgrep -f "$XRAY_BIN run -c $XRAY_CONF" >/dev/null || \
      nohup "$XRAY_BIN" run -c "$XRAY_CONF" >"$STATE_DIR/xray.log" 2>&1 &
    ok "xray запущен (лог: $STATE_DIR/xray.log)"
  fi

  # ждём, пока поднимется, и проверяем, что через туннель есть выход наружу.
  # Страну НЕ проверяем: точка выхода может меняться, и это не важно для работы.
  say "  проверяю, что через туннель есть выход в интернет"
  local egress_ip=""
  for _ in 1 2 3 4 5 6; do
    sleep 2
    egress_ip="$(curl -fsS --max-time 10 -x "http://127.0.0.1:$HTTP_PORT" https://api.ipify.org 2>/dev/null | tr -d '[:space:]')" || egress_ip=""
    [ -n "$egress_ip" ] && break
  done
  if [ -z "$egress_ip" ]; then
    die "через туннель наружу не выходит — xray не поднялся или ссылка нерабочая (лог: journalctl --user -u dgx-xray)"
  else
    ok "туннель работает, точка выхода: $egress_ip"
  fi
}

# =============================================================================
# Фаза 2. Claude Code
# =============================================================================
phase_claude() {
  say "Фаза 2 — Claude Code"
  if have claude; then ok "уже установлен: $(claude --version 2>/dev/null | head -1)"; return; fi

  # ВАЖНО: установщик тянем ЧЕРЕЗ ТУННЕЛЬ. claude.com в ряде регионов отдаёт HTML
  # «App unavailable in region» (гео-блок по прямому IP DGX) вместо скрипта — если такое
  # запустить, будет «синтаксическая ошибка рядом с <». Через туннель выход идёт с
  # поддерживаемого IP. Тот же прокси нужен и самому установщику, чтобы скачать бинарь.
  local proxy="http://127.0.0.1:$HTTP_PORT"
  local dl_ok=0 script=/tmp/claude-install.sh
  say "  качаю установщик через туннель ($proxy)"
  if curl -fsSL --max-time 60 -x "$proxy" https://claude.ai/install.sh -o "$script" 2>/dev/null; then
    dl_ok=1
  elif curl -fsSL --max-time 30 https://claude.ai/install.sh -o "$script" 2>/dev/null; then
    warn "через туннель не вышло — скачал напрямую (проверю содержимое)"; dl_ok=1
  fi

  # Убедиться, что скачали ИМЕННО shell-скрипт, а не гео-заглушку/HTML.
  if [ "$dl_ok" = 1 ] && head -c 512 "$script" | grep -qiE '<!DOCTYPE|<html|app-unavailable-in-region'; then
    warn "установщик вернул HTML (гео-блок «App unavailable in region»), а не скрипт — не запускаю"
    dl_ok=0
  fi

  if [ "$dl_ok" = 1 ]; then
    # бинарь Claude Code тоже качается через туннель
    HTTPS_PROXY="$proxy" HTTP_PROXY="$proxy" bash "$script" || die "официальный установщик Claude Code упал"
  elif have npm; then
    warn "официальный установщик недоступен/гео-блок — ставлю через npm (тоже через туннель)"
    HTTPS_PROXY="$proxy" HTTP_PROXY="$proxy" npm install -g @anthropic-ai/claude-code || die "npm install claude-code упал"
  else
    die "Claude Code не установить: установщик гео-блокируется по прямому IP, npm нет. Поставь Node/npm (тогда пойдёт через туннель) — или проверь, что туннель на 127.0.0.1:$HTTP_PORT жив."
  fi
  have claude || { export PATH="$HOME/.local/bin:$PATH"; }
  have claude && ok "Claude Code установлен: $(claude --version 2>/dev/null | head -1)" \
              || die "claude не появился в PATH — открой новый шелл и проверь"
}

# =============================================================================
# Фаза 3. LiteLLM + PostgreSQL (учёт)
# =============================================================================
DOCKER=""
detect_docker() {
  if docker ps >/dev/null 2>&1; then DOCKER="docker"
  elif sudo -n docker ps >/dev/null 2>&1; then DOCKER="sudo docker"
  else die "docker недоступен без прав. Добавь себя в группу docker (sudo usermod -aG docker $USER; перелогинься) или запусти скрипт с рабочим sudo."; fi
}

phase_litellm() {
  say "Фаза 3 — LiteLLM + PostgreSQL (учёт токенов и денег)"
  have docker || die "docker не установлен. Поставь Docker Engine для aarch64 и повтори (см. 10-bootstrap.md)."
  detect_docker

  # ключи провайдеров
  if [ -z "${ANTHROPIC_API_KEY:-}" ]; then
    read -r -s -p "  Anthropic API key (sk-ant-..., Enter чтобы пропустить): " k; echo
    [ -n "$k" ] && save_secret ANTHROPIC_API_KEY "$k"
  else ok "ANTHROPIC_API_KEY взят из secrets.env"; fi
  if [ -z "${OPENAI_API_KEY:-}" ]; then
    read -r -s -p "  OpenAI API key (sk-..., Enter чтобы пропустить): " k; echo
    [ -n "$k" ] && save_secret OPENAI_API_KEY "$k"
  else ok "OPENAI_API_KEY взят из secrets.env"; fi
  [ -n "${ANTHROPIC_API_KEY:-}" ] || [ -n "${OPENAI_API_KEY:-}" ] \
    || die "не задан ни один ключ — LiteLLM нечем наполнять"

  # служебные секреты
  [ -n "${LITELLM_MASTER_KEY:-}" ] || save_secret LITELLM_MASTER_KEY "sk-$(gen_key)"
  [ -n "${POSTGRES_PASSWORD:-}" ]  || save_secret POSTGRES_PASSWORD "$(gen_key)"

  # конфиг моделей
  if [ ! -f "$LITELLM_CONF" ]; then
    cp "$SCRIPT_DIR/litellm.config.example.yaml" "$LITELLM_CONF"
    ok "конфиг моделей создан из шаблона: $LITELLM_CONF — при желании поправь список моделей"
  else ok "конфиг моделей уже есть: $LITELLM_CONF"; fi

  # поднимаем
  say "  поднимаю контейнеры (образ $LITELLM_IMAGE)"
  ( cd "$SCRIPT_DIR" && \
    LITELLM_CONFIG="$LITELLM_CONF" \
    LITELLM_MASTER_KEY="$LITELLM_MASTER_KEY" \
    POSTGRES_PASSWORD="$POSTGRES_PASSWORD" \
    ANTHROPIC_API_KEY="${ANTHROPIC_API_KEY:-}" \
    OPENAI_API_KEY="${OPENAI_API_KEY:-}" \
    LLM_EGRESS_PROXY="http://127.0.0.1:$HTTP_PORT" \
    $DOCKER compose -f docker-compose.litellm.yml up -d ) \
    || die "docker compose up упал"

  say "  жду, пока LiteLLM ответит на /health/liveliness"
  local up=0
  for _ in $(seq 1 30); do
    if curl -fsS --max-time 5 "http://127.0.0.1:$LITELLM_PORT/health/liveliness" >/dev/null 2>&1; then up=1; break; fi
    sleep 3
  done
  [ "$up" = 1 ] && ok "LiteLLM поднялся на :$LITELLM_PORT" \
    || die "LiteLLM не ответил за ~90с. Логи: $DOCKER logs dgx-litellm"
}

# =============================================================================
# Фаза 4. Настроить Claude Code на LiteLLM
# =============================================================================
phase_configure() {
  say "Фаза 4 — привязываю Claude Code к LiteLLM"
  local sj="$HOME/.claude/settings.json"
  mkdir -p "$HOME/.claude"
  [ -f "$sj" ] || echo '{}' > "$sj"
  # правим только блок env, остальное не трогаем
  python3 - "$sj" "$LITELLM_PORT" "${LITELLM_MASTER_KEY:-}" <<'PY'
import json, sys
path, port, key = sys.argv[1], sys.argv[2], sys.argv[3]
try:
    with open(path) as f: cfg = json.load(f)
except Exception:
    cfg = {}
env = cfg.get("env", {})
env["ANTHROPIC_BASE_URL"] = f"http://127.0.0.1:{port}"
env["ANTHROPIC_AUTH_TOKEN"] = key
env["NO_PROXY"] = "127.0.0.1,localhost"
# намеренно НЕ ставим HTTPS_PROXY в окружение Claude Code:
# его выход — это LiteLLM, а уже LiteLLM уходит в туннель. Слои разделены.
env.pop("HTTPS_PROXY", None)
env.pop("HTTP_PROXY", None)
cfg["env"] = env
with open(path, "w") as f: json.dump(cfg, f, indent=2, ensure_ascii=False)
print("  записано в", path)
PY
  ok "settings.json обновлён: $sj (env: ANTHROPIC_BASE_URL, ANTHROPIC_AUTH_TOKEN, NO_PROXY)"
  warn "если уже запущен фоновый супервизор Claude Code — перечитает не сразу: claude daemon stop --any"
}

# =============================================================================
# Фаза 5. Проверка всей цепочки (эти проверки МОГУТ упасть — так и задумано)
# =============================================================================
phase_verify() {
  say "Фаза 5 — сквозная проверка"
  local fail=0

  # 1. туннель выходит наружу (страну НЕ проверяем — точка выхода может меняться)
  local egress_ip
  egress_ip="$(curl -fsS --max-time 10 -x "http://127.0.0.1:$HTTP_PORT" https://api.ipify.org 2>/dev/null | tr -d '[:space:]')" || egress_ip=""
  if [ -n "$egress_ip" ]; then ok "туннель: выход наружу есть ($egress_ip)"
  else err "туннель не отвечает"; fail=1; fi

  # 2. LiteLLM жив
  if curl -fsS --max-time 5 "http://127.0.0.1:$LITELLM_PORT/health/liveliness" >/dev/null 2>&1; then
    ok "LiteLLM отвечает на :$LITELLM_PORT"
  else err "LiteLLM не отвечает"; fail=1; fi

  # 3. реальный round-trip через LiteLLM: модель -> KZ -> Anthropic/OpenAI и обратно
  local model resp http
  model="$(grep -E '^[[:space:]]*-[[:space:]]*model_name:' "$LITELLM_CONF" 2>/dev/null \
           | head -1 | sed -E 's/.*model_name:[[:space:]]*//; s/[[:space:]]*#.*$//; s/[[:space:]]*$//')"
  if [ -n "$model" ] && [ -n "${LITELLM_MASTER_KEY:-}" ]; then
    resp="$(mktemp)"
    http="$(curl -sS --max-time 40 -o "$resp" -w '%{http_code}' \
      "http://127.0.0.1:$LITELLM_PORT/v1/messages" \
      -H "x-api-key: $LITELLM_MASTER_KEY" \
      -H "anthropic-version: 2023-06-01" \
      -H "content-type: application/json" \
      -d "{\"model\":\"$model\",\"max_tokens\":8,\"messages\":[{\"role\":\"user\",\"content\":\"ping\"}]}" 2>/dev/null || echo 000)"
    if [ "$http" = 200 ]; then
      ok "сквозной запрос к модели '$model' прошёл (HTTP 200) — цепочка работает целиком"
    else
      err "запрос к модели вернул HTTP $http:"
      sed 's/^/       /' "$resp" | head -6 >&2
      fail=1
    fi
    rm -f "$resp"
  else
    warn "пропускаю живой запрос: не нашёл модель в конфиге или master_key"
  fi

  echo
  if [ "$fail" = 0 ]; then
    ok "ГОТОВО. Claude Code ходит в модели через КЗ, учёт в LiteLLM."
    echo "     UI учёта:   http://127.0.0.1:$LITELLM_PORT/ui  (ключ = LITELLM_MASTER_KEY из $SECRETS)"
    echo "     запуск:     claude --model $model"
    echo "     проверка что байты реально идут через КЗ: открой x-ui на VPS — счётчики должны расти во время сессии."
  else
    die "есть проваленные проверки выше — цепочка собрана не полностью"
  fi
}

# =============================================================================
main() {
  [ "$SKIP_DIAGNOSE" = 1 ] && warn "фаза диагностики пропущена (--skip-diagnose)" || phase_diagnose
  [ "$DO_DIAGNOSE_ONLY" = 1 ] && { echo; say "только диагностика — ничего не устанавливал"; exit 0; }
  echo
  say "Дальше скрипт будет СТАВИТЬ и НАСТРАИВАТЬ. Секреты сохранятся в $SECRETS (chmod 600)."
  ask "Продолжить установку?" || { say "остановлено по твоему выбору"; exit 0; }

  init_secrets
  [ "$SKIP_XRAY" = 1 ]      && warn "фаза xray пропущена (--skip-xray)"           || phase_xray
  [ "$SKIP_CLAUDE" = 1 ]    && warn "фаза Claude Code пропущена (--skip-claude)"  || phase_claude
  [ "$SKIP_LITELLM" = 1 ]   && warn "фаза LiteLLM пропущена (--skip-litellm)"     || phase_litellm
  [ "$SKIP_CONFIGURE" = 1 ] && warn "фаза configure пропущена (--skip-configure)" || phase_configure
  [ "$SKIP_VERIFY" = 1 ]    && warn "фаза verify пропущена (--skip-verify)"        || phase_verify
}
main
