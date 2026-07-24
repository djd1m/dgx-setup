#!/usr/bin/env bash
# =============================================================================
# install-lm-studio.sh
#
# Ставит LM Studio в headless-варианте (демон llmster + CLI lms) на DGX Spark /
# GB10 (aarch64, DGX OS) и поднимает OpenAI-совместимый сервер на порту 1234.
# GUI (AppImage) НЕ ставится — на SSH-сервере он не нужен: официальный путь для
# Spark — llmster (так делает и плейбук NVIDIA:
# https://github.com/NVIDIA/dgx-spark-playbooks/tree/main/nvidia/lm-studio).
#
# Проверено 2026-07-24 (см. research/lm-studio-vs-ollama-dgx.md):
#   - install.sh официальный, ставит llmster в ~/.lmstudio/bin, есть linux-arm64;
#   - раздача за Cloudflare -> из РФ может виснуть, поэтому есть --proxy;
#   - порт у lms server "последний использованный" -> задаём --port явно;
#   - у LM Studio НЕТ Anthropic-API (/v1/messages) -> Claude Code напрямую НЕ
#     подключить (это умеет Ollama). Для OpenAI-клиентов (Hermes и т.п.) — ок.
#
# Запуск:
#   bash install-lm-studio.sh                        # поставить + сервер на 1234
#   bash install-lm-studio.sh --model openai/gpt-oss-20b   # + скачать и держать модель
#   bash install-lm-studio.sh --proxy https://адрес  # качать через прокси (Cloudflare-блокировка)
#   bash install-lm-studio.sh --lan                  # слушать 0.0.0.0 (только доверенная сеть!)
#   bash install-lm-studio.sh --autostart            # systemd-юнит автозапуска (официальный рецепт)
#   bash install-lm-studio.sh --diagnose             # только проверки, ничего не менять
#   bash install-lm-studio.sh --remove               # убрать демон и юнит (модели остаются)
# =============================================================================
set -euo pipefail

LMS="$HOME/.lmstudio/bin/lms"
PORT=1234
UNIT=/etc/systemd/system/lmstudio.service
MODEL=""; LAN=0; AUTOSTART=0; REMOVE=0; DIAGNOSE=0
PROXY="${HTTPS_PROXY:-}"

next=""
for a in "$@"; do
  if [ -n "$next" ]; then
    case "$next" in model) MODEL="$a";; proxy) PROXY="$a";; port) PORT="$a";; esac
    next=""; continue
  fi
  case "$a" in
    --model)    next=model ;;
    --model=*)  MODEL="${a#--model=}" ;;
    --proxy)    next=proxy ;;
    --proxy=*)  PROXY="${a#--proxy=}" ;;
    --port)     next=port ;;
    --port=*)   PORT="${a#--port=}" ;;
    --lan)      LAN=1 ;;
    --autostart) AUTOSTART=1 ;;
    --diagnose) DIAGNOSE=1 ;;
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
  say "Убираю llmster"
  if [ -f "$UNIT" ]; then
    sudo systemctl disable --now lmstudio.service 2>/dev/null || true
    sudo rm -f "$UNIT" && sudo systemctl daemon-reload
    ok "systemd-юнит удалён"
  fi
  [ -x "$LMS" ] && { "$LMS" daemon down 2>/dev/null || true; ok "демон остановлен"; }
  warn "бинарники и МОДЕЛИ остаются в ~/.lmstudio (модели тяжёлые — удалять их или нет, решай сам):"
  warn "  rm -rf ~/.lmstudio    # полное удаление, включая скачанные модели"
  exit 0
fi

# --- самодиагностика: железо и предусловия ----------------------------------
say "Проверяю железо и предусловия"
have curl || die "нужен curl"

ARCH="$(uname -m)"
case "$ARCH" in
  aarch64) ok "архитектура: aarch64 (DGX Spark / GB10) — есть официальная сборка linux-arm64" ;;
  x86_64)  ok "архитектура: x86_64 — сборка linux-x64 тоже есть" ;;
  *)       die "архитектура $ARCH не поддерживается установщиком LM Studio" ;;
esac

if have nvidia-smi; then
  drv="$(nvidia-smi --query-gpu=driver_version --format=csv,noheader 2>/dev/null | head -1 | cut -d. -f1 || true)"
  if [ -n "$drv" ] && [ "$drv" -ge 550 ] 2>/dev/null; then
    ok "драйвер NVIDIA: $(nvidia-smi --query-gpu=driver_version --format=csv,noheader 2>/dev/null | head -1)"
  else
    warn "драйвер NVIDIA не определился или старее 550 — GPU-инференс под вопросом (см. for-ai/00-ollama.md, Шаг П2)"
  fi
  nvidia-smi -L 2>/dev/null | grep -q GB10 && ok "GPU: GB10 — движок LM Studio под CUDA 13 заявлен официально"
else
  warn "nvidia-smi нет — без GPU llmster заработает, но инференс будет процессорным (медленно)"
fi

# libatomic обязателен: официальный install.sh без него останавливается
if ldconfig -p 2>/dev/null | grep -q 'libatomic.so.1'; then
  ok "libatomic1 на месте"
else
  warn "нет libatomic1 (обязателен для llmster) — пробую поставить"
  if sudo apt-get install -y libatomic1; then ok "libatomic1 установлен"
  else die "не удалось поставить libatomic1 — поставь вручную: sudo apt-get install -y libatomic1"; fi
fi

if [ "$DIAGNOSE" = 1 ] && [ ! -x "$LMS" ]; then
  say "только диагностика: llmster ещё не установлен, предусловия выше. Ничего не менял."; exit 0
fi

# --- установка llmster -------------------------------------------------------
if [ -x "$LMS" ]; then
  ok "llmster уже установлен: $("$LMS" version 2>/dev/null | head -1 || echo '(версия не определилась)')"
else
  say "Ставлю llmster официальным установщиком lmstudio.ai/install.sh"
  script=/tmp/lmstudio-install.sh
  [ -n "$PROXY" ] && export HTTPS_PROXY="$PROXY" && ok "качаю через прокси: $PROXY"
  curl -fsSL --retry 3 --max-time 60 https://lmstudio.ai/install.sh -o "$script" \
    || die "не скачался install.sh — проверь сеть (или задай --proxy)"
  head -c 256 "$script" | grep -qiE '<!DOCTYPE|<html' \
    && die "вместо установщика пришёл HTML (блокировка на пути) — перезапусти с --proxy"
  warn "дальше установщик скачает ~сотни МБ с llmster.lmstudio.ai (Cloudflare)."
  warn "Если скачивание ВИСНЕТ — это блокировка провайдером Cloudflare-трафика: Ctrl+C и перезапуск с --proxy"
  bash "$script" || die "установщик llmster завершился с ошибкой"
  [ -x "$LMS" ] || die "после установки нет $LMS — смотри вывод установщика"
  ok "llmster установлен: $LMS"
fi

if [ "$DIAGNOSE" = 1 ]; then
  say "только диагностика — статус демона:"; "$LMS" daemon status || true; exit 0
fi

# --- демон + сервер ----------------------------------------------------------
say "Поднимаю демон и API-сервер"
"$LMS" daemon up || die "lms daemon up не отработал"
ok "демон: $("$LMS" daemon status 2>/dev/null | head -1 || echo up)"

BIND=127.0.0.1
if [ "$LAN" = 1 ]; then
  BIND=0.0.0.0
  warn "сервер будет слушать 0.0.0.0:$PORT — авторизации у него НЕТ, только доверенная сеть!"
fi
# порт задаём явно: по докам lms без --port берёт «последний использованный», а не 1234
"$LMS" server start --bind "$BIND" --port "$PORT" || die "lms server start не отработал"
ok "сервер: http://$BIND:$PORT (OpenAI-совместимый /v1)"

# --- модель (опционально) ----------------------------------------------------
if [ -n "$MODEL" ]; then
  say "Скачиваю и загружаю модель: $MODEL"
  warn "модели качаются с huggingface.co; если виснет — у LM Studio нет HF-зеркал для CLI,"
  warn "включить встроенный HF-прокси можно только из GUI (research/lm-studio-vs-ollama-dgx.md, п.1)"
  "$LMS" get "$MODEL" || die "не скачалась модель $MODEL (lms get)"
  # --yes: без вопросов; контекст 64000 — минимум для агентов (см. 00-ollama.md про Hermes);
  # без --ttl модель остаётся в памяти навсегда (JIT-модели выгружаются через 60 минут простоя)
  "$LMS" load "$MODEL" --yes --context-length 64000 || die "не загрузилась модель $MODEL (lms load)"
  ok "модель загружена и останется в памяти (без TTL)"
fi

# --- смоук-тест --------------------------------------------------------------
say "Смоук-тест API"
mj="$(curl -fsS -m 10 "http://127.0.0.1:$PORT/v1/models" 2>/dev/null || true)"
if printf '%s' "$mj" | grep -q '"data"'; then
  ok "/v1/models отвечает"
else
  die "нет ответа от http://127.0.0.1:$PORT/v1/models — смотри lms log stream"
fi
if [ -n "$MODEL" ]; then
  code="$(curl -s -o /tmp/lms-chat.json -w '%{http_code}' -m 120 "http://127.0.0.1:$PORT/v1/chat/completions" \
    -H 'Content-Type: application/json' \
    -d "{\"model\":\"$MODEL\",\"max_tokens\":16,\"messages\":[{\"role\":\"user\",\"content\":\"скажи привет одним словом\"}]}" || echo 000)"
  if [ "$code" = 200 ]; then
    ok "чат отвечает (HTTP 200): $(grep -o '"content":"[^"]*"' /tmp/lms-chat.json | head -1)"
  else
    warn "чат вернул HTTP $code — модель могла ещё грузиться, повтори запрос позже"
  fi
fi

# --- автозапуск (опционально) ------------------------------------------------
if [ "$AUTOSTART" = 1 ]; then
  say "Настраиваю автозапуск (официальный systemd-рецепт LM Studio)"
  # https://lmstudio.ai/docs/developer/core/headless_llmster — пути абсолютные, systemd не знает ~
  LOAD_LINE=""
  [ -n "$MODEL" ] && LOAD_LINE="ExecStartPre=$HOME/.lmstudio/bin/lms load $MODEL --yes --context-length 64000"
  sudo tee "$UNIT" > /dev/null <<EOF
[Unit]
Description=LM Studio Server

[Service]
Type=oneshot
RemainAfterExit=yes
User=$USER
Environment="HOME=$HOME"
ExecStartPre=$HOME/.lmstudio/bin/lms daemon up
$LOAD_LINE
ExecStart=$HOME/.lmstudio/bin/lms server start --bind $BIND --port $PORT
ExecStop=$HOME/.lmstudio/bin/lms daemon down

[Install]
WantedBy=multi-user.target
EOF
  sudo systemctl daemon-reload
  sudo systemctl enable lmstudio.service
  ok "автозапуск включён: systemctl status lmstudio.service"
fi

# --- итог --------------------------------------------------------------------
echo
say "Готово."
echo "  API:        http://127.0.0.1:$PORT/v1  (OpenAI-совместимый; Anthropic-API НЕТ — для Claude Code бери Ollama)"
echo "  Модели:     $LMS get <имя>   и   $LMS load <имя> --yes"
echo "  Статус:     $LMS ps   |   $LMS daemon status"
echo "  Логи:       $LMS log stream"
[ "$AUTOSTART" = 1 ] || echo "  Автозапуск: перезапусти скрипт с --autostart"
[ -z "$MODEL" ] && echo "  Модель не ставилась. Для Spark бери MoE (см. for-human/15-lm-studio.md), напр.: --model openai/gpt-oss-20b"
warn "скорость на GB10 решает тип модели (MoE!), а не размер — правило из 00-ollama.md действует и тут"
