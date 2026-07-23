# Ресёрч: установка OpenAI Codex CLI + автоопределение окружения

> Верифицировано по исходникам (README, `codex-cli/package.json`, официальный `install.sh`,
> Rust-исходник, доки ChatGPT), 2026-07-23. Основа для `scripts/install-claude-codex.sh`.
> Неподтверждённое — **NOT VERIFIED**.

## Матрица установки Codex

Источник: [github.com/openai/codex](https://github.com/openai/codex)
([README](https://raw.githubusercontent.com/openai/codex/main/README.md)),
[docs/install.md](https://raw.githubusercontent.com/openai/codex/main/docs/install.md).

| Способ | Команда | Node? |
|---|---|---|
| native (macOS/Linux) | `curl -fsSL https://chatgpt.com/codex/install.sh \| sh` | **не нужен** (бинарь на Rust) |
| native (Windows) | `powershell -ExecutionPolicy ByPass -c "irm https://chatgpt.com/codex/install.ps1 \| iex"` | не нужен |
| Homebrew | `brew install --cask codex` (это **cask**, не formula) | не нужен |
| npm | `npm install -g @openai/codex` | **Node ≥16** (тонкая JS-обёртка) |
| нативный бинарь | GitHub Releases, тег `rust-v<x.y.z>` | не нужен |

**Node-нюанс (verified):** нативный бинарь на Rust — Node не нужен. npm-пакет —
JS-обёртка, `codex-cli/package.json` объявляет `"engines": {"node": ">=16"}`. Корневой
`package.json` монорепо (`node >=22`) относится к **сборке репо**, не к CLI — не путать.
Источник: [codex-cli/package.json](https://raw.githubusercontent.com/openai/codex/main/codex-cli/package.json).

**Ассеты релизов** (из `install.sh`): `codex-{aarch64,x86_64}-apple-darwin.tar.gz`,
`codex-{aarch64,x86_64}-unknown-linux-musl.tar.gz` (musl = статик, дистро-агностик).

**Поддержка ОС** ([docs/install.md](https://raw.githubusercontent.com/openai/codex/main/docs/install.md)):
macOS 12+, Ubuntu 20.04+/Debian 10+, Windows 11 через WSL2. Минимум 4 ГБ RAM.

**Пути:** бинарь → `$HOME/.local/bin/codex` (override `CODEX_INSTALL_DIR`); конфиг → `~/.codex`
(override `CODEX_HOME`), там `config.toml` и `auth.json`. Проверка: `codex --version`.

**Логин** ([auth](https://learn.chatgpt.com/docs/auth)): `codex login` (ChatGPT OAuth) либо
`printenv OPENAI_API_KEY | codex login --with-api-key` (ключ через stdin). `auth.json` —
plaintext, обращаться как с секретом.

## Cookbook автоопределения окружения (проверено по Codex `install.sh`)

Референс — [официальный install.sh](https://chatgpt.com/codex/install.sh) (POSIX `sh`, `set -eu`).

```sh
# ОС
case "$(uname -s)" in Linux) OS=linux;; Darwin) OS=macos;; *) OS=unknown;; esac

# дистрибутив (freedesktop os-release)
[ -r /etc/os-release ] && . /etc/os-release   # $ID, $ID_LIKE, $VERSION_ID

# WSL
grep -qiE 'microsoft|WSL' /proc/version 2>/dev/null || [ -n "${WSL_DISTRO_NAME:-}" ]

# арх + нормализация + Rosetta
case "$(uname -m)" in x86_64|amd64) ARCH=x86_64;; arm64|aarch64) ARCH=aarch64;; esac
[ "$OS" = macos ] && [ "$ARCH" = x86_64 ] && \
  [ "$(sysctl -n sysctl.proc_translated 2>/dev/null)" = 1 ] && ARCH=aarch64

# пакетный менеджер (по приоритету, POSIX command -v — не which)
for pm in apt-get dnf yum pacman zypper apk brew; do command -v "$pm" >/dev/null 2>&1 && { PM=$pm; break; }; done

# node presence + версия (npm-путь требует >=16)
command -v node >/dev/null && [ "$(node -v | sed 's/^v//;s/\..*//')" -ge 16 ]

# права
[ "$(id -u)" -eq 0 ] && SUDO= || { command -v sudo >/dev/null && SUDO=sudo || SUDO=; }

# загрузчик
command -v curl >/dev/null && DL=curl || { command -v wget >/dev/null && DL=wget; }
```

Семейства PM: apt-get→debian/ubuntu, dnf/yum→fedora/rhel, pacman→arch, zypper→opensuse,
apk→alpine, brew→macOS. Node-фолбэки: пакетный менеджер → [NodeSource](https://github.com/nodesource/distributions)
→ [nvm](https://github.com/nvm-sh/nvm) → [nodejs.org/dist](https://nodejs.org/dist/).

## MCP (для codex-плагина Claude Code)

Два разных подкоманд (verified в [codex-rs/cli/src/main.rs](https://raw.githubusercontent.com/openai/codex/main/codex-rs/cli/src/main.rs)):
- **`codex mcp-server`** — «Start Codex as an MCP server (stdio)» → это и подключают в Claude Code.
- **`codex mcp add <name> -- <cmd>`** — добавить ВНЕШНИЕ MCP-серверы В Codex (другое).

Подробности интеграции — [codex-plugin-claude-code.md](codex-plugin-claude-code.md).

**Вывод для установщика:** для универсальности предпочитать **native curl/PowerShell** путь
Codex (снимает зависимость от Node, бинарь сам разбирается с арх/ОС/Rosetta); npm — только
как фолбэк при наличии Node ≥16.
