# Ресёрч: Codex-плагин для Claude Code

> ⚠️ **Исправлено 2026-07-23.** Первая версия этого файла ошибочно утверждала, что
> официального «codex-плагина» нет. Это НЕВЕРНО: у OpenAI есть официальный плагин
> [openai/codex-plugin-cc](https://github.com/openai/codex-plugin-cc). Ниже — верные факты,
> проверенные по его README.

## Официальный плагин (главный способ)

Репозиторий: [openai/codex-plugin-cc](https://github.com/openai/codex-plugin-cc). Плагин
интегрирует Codex в Claude Code слэш-командами: code review и делегирование задач Codex
не выходя из Claude Code.

**Предусловия:** Node.js 18.18+, установленный и **залогиненный** Codex CLI, подписка
ChatGPT (в т.ч. Free) ИЛИ ключ OpenAI.

**Установка** (слэш-команды в сессии Claude Code):
```
/plugin marketplace add openai/codex-plugin-cc
/plugin install codex@openai-codex
/reload-plugins
/codex:setup        # проверка; при отсутствии Codex может доустановить через npm
!codex login        # если Codex ещё не залогинен
```

**Через CLI (неинтерактивно — это и делает `scripts/install-codex-plugin.sh`):**
```bash
claude plugin marketplace add openai/codex-plugin-cc
claude plugin install codex@openai-codex -s user
claude plugin list          # проверить
```

**Команды плагина:** `/codex:review` (стандартный ревью), `/codex:adversarial-review`
(челлендж-ревью), `/codex:rescue` (делегировать задачу Codex), `/codex:status`,
`/codex:result`, `/codex:cancel` (фоновые задачи).

**Конфиг модели Codex:** `~/.codex/config.toml` (user) или `.codex/config.toml` (проект):
```toml
model = "gpt-5.4-mini"
model_reasoning_effort = "high"
```

## Альтернатива: Codex как MCP-сервер (если не нужен плагин)

У Codex CLI есть подкоманда **`codex mcp-server`** (*«Start Codex as an MCP server (stdio)»*,
verified в [codex-rs/cli/src/main.rs](https://raw.githubusercontent.com/openai/codex/main/codex-rs/cli/src/main.rs)).
Её можно зарегистрировать в Claude Code напрямую, без плагина:
```bash
claude mcp add codex -s user -- codex mcp-server
```
Это даёт Claude Code вызывать Codex как MCP-инструмент, но без готовых слэш-команд ревью,
которые даёт официальный плагин. Не путать с `codex mcp add <name> -- <cmd>` (обратное —
добавить внешние MCP-серверы В Codex).

**Вывод:** для интеграции Codex в Claude Code — ставь **официальный плагин**
(`scripts/install-codex-plugin.sh`); MCP-регистрация — запасной вариант.
