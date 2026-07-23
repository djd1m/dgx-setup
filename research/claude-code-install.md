# Ресёрч: установка Claude Code на любой ОС + плагины

> Верифицировано по официальной документации Claude Code (2026-07-23). Основа для
> `scripts/install-claude-codex.sh`. Неподтверждённое помечено **NOT VERIFIED**.

## Матрица установки

Источник: [code.claude.com/docs/en/setup](https://code.claude.com/docs/en/setup.md),
[troubleshoot-install](https://code.claude.com/docs/en/troubleshoot-install.md).

| ОС | Арх | Рекомендованный способ | Команда | Node? |
|---|---|---|---|---|
| macOS | arm64/Intel | native / Homebrew | `curl -fsSL https://claude.ai/install.sh \| bash` | не нужен |
| Linux (Debian/Ubuntu) | x86_64/arm64 | native / apt | `curl -fsSL https://claude.ai/install.sh \| bash` | не нужен |
| Alpine | x86_64/arm64 | native + зависимости | `apk add bash curl libgcc libstdc++ ripgrep` затем installer | не нужен |
| Fedora/RHEL | x86_64/arm64 | native / dnf | installer | не нужен |
| Windows (native) | x64/arm64 | PowerShell | `irm https://claude.ai/install.ps1 \| iex` | не нужен |
| Windows WSL2 | x64/arm64 | native (внутри WSL) | `curl -fsSL https://claude.ai/install.sh \| bash` | не нужен |
| любая (npm) | x86_64/arm64 | npm | `npm install -g @anthropic-ai/claude-code` | **Node 22+** реком. |

**Ключевое:** native-инсталлер скачивает нативный бинарь и **Node не требует**. Node нужен
только для npm-пути. На Alpine нет встроенного `ripgrep` — доставить зависимости до installer.

**Куда ставится:** native/npm → `~/.local/bin/claude` (симлинк на `~/.local/share/claude/versions/<v>/`);
Homebrew → `/opt/homebrew/bin` (arm64) или `/usr/local/bin` (Intel); apt/dnf/apk → `/usr/bin/claude`.
Конфиг — всегда `~/.claude/`.

**Проверка установки:** `claude --version` (напр. `2.1.218 (Claude Code)`), `claude doctor`
(PATH/settings/hooks).

## Плагины Claude Code — как устроены

Источник: [discover-plugins](https://code.claude.com/docs/en/discover-plugins.md),
[plugins-reference](https://code.claude.com/docs/en/plugins-reference.md).

- Плагин — директория (`plugin.json` + `skills/` + опц. `mcp/`), ставится в `~/.claude/plugins/`
  (user) или `.claude/plugins/` (project).
- Команды: `/plugin marketplace add <owner/repo>`, `/plugin install <name>@<marketplace>`,
  `/plugin list`, `/plugin disable`.
- Официальный маркетплейс — `claude-plugins-official` (напр. Slack: `/plugin install slack@claude-plugins-official`).

## Два важных вывода для наших скриптов

- **Официального Telegram-плагина НЕТ** — ни в official, ни в community маркетплейсе. Telegram
  подключается только community-мостами (см. [telegram-claude-code.md](telegram-claude-code.md)).
- **Встроенного «codex-плагина» НЕТ** — Codex подключается как MCP-сервер
  (см. [codex-plugin-claude-code.md](codex-plugin-claude-code.md)). Общий механизм MCP:
  [mcp-quickstart](https://code.claude.com/docs/en/mcp-quickstart.md), синтаксис
  `claude mcp add [-t stdio|http] [-s local|user|project] <name> <cmd|url> [args...]`.
