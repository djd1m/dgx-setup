#!/usr/bin/env bash
# =============================================================================
# install-claude-codex.sh
#
# Универсальный установщик Claude Code + OpenAI Codex CLI на ЛЮБОЙ сервер.
# Запускается на любой ОС/архитектуре, сам определяет окружение и выбирает
# оптимальный способ установки каждого инструмента.
#
# Запуск:
#   bash install-claude-codex.sh            # поставить оба (claude + codex)
#   bash install-claude-codex.sh --only claude
#   bash install-claude-codex.sh --only codex
#   bash install-claude-codex.sh --diagnose # только показать окружение, ничего не ставить
#   bash install-claude-codex.sh --method npm   # форсировать npm вместо native-инсталлера
#   bash install-claude-codex.sh --yes      # не переспрашивать
#
# Идемпотентен: повторный запуск не ломает уже установленное.
#
# Проверенные факты, на которых построен выбор способа (со ссылками — в
# ../research/claude-code-install.md и ../research/codex-install.md):
#   - Claude Code native-инсталлер: https://claude.ai/install.sh — БЕЗ Node.
#   - Codex native-инсталлер:       https://chatgpt.com/codex/install.sh — БЕЗ Node (бинарь на Rust).
#   - npm-путь у обоих требует Node (Claude: 22+ рекоменд.; Codex: >=16).
#   - Оба по умолчанию ставятся в ~/.local/bin (root не нужен).
# =============================================================================
set -euo pipefail

# --- флаги ------------------------------------------------------------------
ONLY=""; METHOD="auto"; ASSUME_YES=0; DIAGNOSE_ONLY=0
next=""
for a in "$@"; do
  if [ -n "$next" ]; then case "$next" in only) ONLY="$a";; method) METHOD="$a";; esac; next=""; continue; fi
  case "$a" in
    --only)     next=only ;;
    --only=*)   ONLY="${a#--only=}" ;;
    --method)   next=method ;;
    --method=*) METHOD="${a#--method=}" ;;
    --yes|-y)   ASSUME_YES=1 ;;
    --diagnose) DIAGNOSE_ONLY=1 ;;
    -h|--help)  grep -E '^#( |$)' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "Неизвестный флаг: $a (см. --help)"; exit 2 ;;
  esac
done
case "$METHOD" in auto|native|npm) ;; *) echo "--method: auto|native|npm"; exit 2 ;; esac
case "$ONLY" in ""|claude|codex) ;; *) echo "--only: claude|codex"; exit 2 ;; esac

# --- вывод ------------------------------------------------------------------
if [ -t 1 ]; then C_G=$'\033[32m'; C_Y=$'\033[33m'; C_R=$'\033[31m'; C_B=$'\033[36m'; C_0=$'\033[0m'
else C_G=; C_Y=; C_R=; C_B=; C_0=; fi
say()  { printf '%s\n' "${C_B}==>${C_0} $*"; }
ok()   { printf '%s\n' "  ${C_G}OK${C_0}   $*"; }
warn() { printf '%s\n' "  ${C_Y}!!${C_0}   $*"; }
err()  { printf '%s\n' "  ${C_R}XX${C_0}   $*" >&2; }
die()  { err "$*"; exit 1; }
ask()  { [ "$ASSUME_YES" = 1 ] && return 0; printf '%s [y/N] ' "$*"; read -r r; case "$r" in y|Y|yes) return 0;; *) return 1;; esac; }

# =============================================================================
# Определение окружения (см. cookbook в ../research/codex-install.md)
# =============================================================================
OS=unknown DISTRO="" ARCH=unknown IS_WSL=0 PM=none SUDO="" DL=""

detect_env() {
  case "$(uname -s)" in
    Linux)  OS=linux ;;
    Darwin) OS=macos ;;
    *)      OS=unknown ;;
  esac

  # WSL
  if grep -qiE 'microsoft|WSL' /proc/version 2>/dev/null || [ -n "${WSL_DISTRO_NAME:-}" ]; then IS_WSL=1; fi

  # дистрибутив Linux
  if [ "$OS" = linux ] && [ -r /etc/os-release ]; then
    # shellcheck disable=SC1091
    DISTRO="$(. /etc/os-release 2>/dev/null; echo "${ID:-}")"
  fi

  # архитектура + нормализация
  case "$(uname -m)" in
    x86_64|amd64)   ARCH=x86_64 ;;
    arm64|aarch64)  ARCH=aarch64 ;;
    *)              ARCH="$(uname -m)" ;;
  esac
  # Rosetta 2: arm64-Mac, притворяющийся x86_64
  if [ "$OS" = macos ] && [ "$ARCH" = x86_64 ] && [ "$(sysctl -n sysctl.proc_translated 2>/dev/null || echo 0)" = "1" ]; then
    ARCH=aarch64
  fi

  # пакетный менеджер (по приоритету)
  for pm in apt-get dnf yum pacman zypper apk brew; do
    if command -v "$pm" >/dev/null 2>&1; then PM="$pm"; break; fi
  done

  # права
  if [ "$(id -u)" -eq 0 ]; then SUDO=""
  elif command -v sudo >/dev/null 2>&1; then SUDO="sudo"
  else SUDO=""; fi

  # загрузчик
  if command -v curl >/dev/null 2>&1; then DL=curl
  elif command -v wget >/dev/null 2>&1; then DL=wget
  else DL=""; fi
}

fetch() { # fetch <url>  -> stdout
  case "$DL" in
    curl) curl -fsSL "$1" ;;
    wget) wget -qO- "$1" ;;
    *) die "нужен curl или wget" ;;
  esac
}

have() { command -v "$1" >/dev/null 2>&1; }

node_major() { have node && node -v 2>/dev/null | sed 's/^v//; s/\..*//' || echo 0; }

pm_install() { # pm_install <пакеты...>
  [ "$PM" = none ] && { warn "пакетный менеджер не найден — поставь вручную: $*"; return 1; }
  case "$PM" in
    apt-get) $SUDO apt-get update -qq && $SUDO apt-get install -y "$@" ;;
    dnf)     $SUDO dnf install -y "$@" ;;
    yum)     $SUDO yum install -y "$@" ;;
    pacman)  $SUDO pacman -Sy --noconfirm "$@" ;;
    zypper)  $SUDO zypper install -y "$@" ;;
    apk)     $SUDO apk add "$@" ;;
    brew)    brew install "$@" ;;
  esac
}

ensure_path_local_bin() {
  case ":$PATH:" in *":$HOME/.local/bin:"*) : ;; *)
    warn "$HOME/.local/bin не в PATH — добавь в ~/.bashrc:  export PATH=\"\$HOME/.local/bin:\$PATH\""
    export PATH="$HOME/.local/bin:$PATH" ;;
  esac
}

# =============================================================================
# Диагностика
# =============================================================================
phase_diagnose() {
  say "Окружение"
  ok "ОС:          $OS${IS_WSL:+}$([ "$IS_WSL" = 1 ] && echo ' (WSL)')"
  ok "дистрибутив: ${DISTRO:-—}"
  ok "архитектура: $ARCH"
  ok "пакетный мгр: $PM"
  ok "загрузчик:   ${DL:-НЕТ (нужен curl/wget)}"
  ok "root/sudo:   $([ "$(id -u)" -eq 0 ] && echo root || { [ -n "$SUDO" ] && echo 'sudo' || echo 'нет (user-local)'; })"
  ok "node:        $(have node && node -v || echo 'нет')"
  ok "claude:      $(have claude && claude --version 2>/dev/null | head -1 || echo 'не установлен')"
  ok "codex:       $(have codex && codex --version 2>/dev/null | head -1 || echo 'не установлен')"
  if [ "$OS" = unknown ]; then
    warn "ОС не Linux/macOS. Для нативного Windows этот bash-скрипт не подходит —"
    warn "  Claude Code:  powershell -c \"irm https://claude.ai/install.ps1 | iex\""
    warn "  Codex:        powershell -ExecutionPolicy ByPass -c \"irm https://chatgpt.com/codex/install.ps1 | iex\""
    warn "  либо запусти этот скрипт внутри WSL2."
  fi
}

# =============================================================================
# Claude Code
# =============================================================================
install_claude() {
  if have claude; then ok "Claude Code уже стоит: $(claude --version 2>/dev/null | head -1)"; return 0; fi
  say "Ставлю Claude Code"

  # Alpine: нативному бинарю нужны зависимости
  if [ "$DISTRO" = alpine ]; then
    say "  Alpine — доставляю зависимости (bash curl libgcc libstdc++ ripgrep)"
    pm_install bash curl libgcc libstdc++ ripgrep || warn "не все зависимости встали — установка может упасть"
  fi

  local m="$METHOD"
  if [ "$m" = auto ]; then
    if [ -n "$DL" ]; then m=native; else m=npm; fi
  fi

  if [ "$m" = native ]; then
    [ -n "$DL" ] || die "native-инсталлеру нужен curl/wget"
    say "  native-инсталлер (https://claude.ai/install.sh) — Node не требуется"
    fetch https://claude.ai/install.sh | bash || die "native-инсталлер Claude Code упал (попробуй --method npm)"
  else
    say "  npm (@anthropic-ai/claude-code)"
    have npm || { warn "npm нет — ставлю Node через пакетный менеджер"; pm_install nodejs npm || die "не смог поставить Node"; }
    [ "$(node_major)" -ge 18 ] || warn "Node $(node -v 2>/dev/null) старый — Claude Code рекомендует 22+"
    npm install -g @anthropic-ai/claude-code || die "npm install @anthropic-ai/claude-code упал"
  fi

  ensure_path_local_bin
  have claude && ok "Claude Code: $(claude --version 2>/dev/null | head -1)" || die "claude не найден после установки (проверь PATH)"
}

# =============================================================================
# Codex CLI
# =============================================================================
install_codex() {
  if have codex; then ok "Codex уже стоит: $(codex --version 2>/dev/null | head -1)"; return 0; fi
  say "Ставлю OpenAI Codex CLI"

  local m="$METHOD"
  if [ "$m" = auto ]; then
    if [ "$OS" = macos ] && [ "$PM" = brew ]; then m=brew
    elif [ -n "$DL" ]; then m=native
    else m=npm; fi
  fi

  case "$m" in
    brew)
      say "  Homebrew cask (brew install --cask codex)"
      brew install --cask codex || { warn "cask не встал — откат на native"; m=native; }
      ;;
  esac
  if [ "$m" = native ]; then
    [ -n "$DL" ] || die "native-инсталлеру нужен curl/wget"
    say "  native-инсталлер (https://chatgpt.com/codex/install.sh) — Node не требуется (бинарь на Rust)"
    fetch https://chatgpt.com/codex/install.sh | sh || die "native-инсталлер Codex упал (попробуй --method npm)"
  elif [ "$m" = npm ]; then
    say "  npm (@openai/codex)"
    have npm || { warn "npm нет — ставлю Node"; pm_install nodejs npm || die "не смог поставить Node"; }
    [ "$(node_major)" -ge 16 ] || die "Codex npm-пакет требует Node >=16 (у тебя $(node -v 2>/dev/null || echo нет))"
    npm install -g @openai/codex || die "npm install @openai/codex упал"
  fi

  ensure_path_local_bin
  have codex && ok "Codex: $(codex --version 2>/dev/null | head -1)" || die "codex не найден после установки (проверь PATH)"
}

# =============================================================================
main() {
  detect_env
  phase_diagnose
  [ "$DIAGNOSE_ONLY" = 1 ] && { echo; say "только диагностика — ничего не ставил"; exit 0; }
  [ -z "$DL" ] && [ "$METHOD" != npm ] && die "нет ни curl, ни wget — поставь один из них (или используй --method npm при наличии npm)"

  echo
  say "Ставлю: ${ONLY:-claude + codex}  (способ: $METHOD)"
  ask "Продолжить?" || { say "остановлено"; exit 0; }
  echo

  [ "$ONLY" = codex ]  || install_claude
  [ "$ONLY" = claude ] || install_codex

  echo
  say "Готово. Дальше:"
  [ "$ONLY" = codex ]  || echo "  • Claude Code: 'claude' — при первом запуске пройдёт вход/настройка."
  [ "$ONLY" = claude ] || echo "  • Codex: 'codex login' (ChatGPT OAuth) либо 'printenv OPENAI_API_KEY | codex login --with-api-key'."
  echo "  • Подключить Codex как MCP-сервер в Claude Code: см. install-codex-plugin.sh."
}
main
