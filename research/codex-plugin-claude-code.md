# Ресёрч: «Codex-плагин» для Claude Code = MCP-сервер

> Верифицировано по докам Claude Code и исходникам Codex (2026-07-23). Основа для
> `scripts/install-codex-plugin.sh`.

## Главный вывод

**Отдельного встроенного «codex-плагина» для Claude Code не существует** (проверено по
маркетплейсам плагинов Claude Code). Штатный способ интеграции — подключить Codex как
**MCP-сервер**: у Codex CLI есть подкоманда **`codex mcp-server`** (*«Start Codex as an MCP
server (stdio)»*, verified в
[codex-rs/cli/src/main.rs](https://raw.githubusercontent.com/openai/codex/main/codex-rs/cli/src/main.rs)),
а Claude Code добавляет её через `claude mcp add`.

## Как подключить (точный синтаксис, проверен на живом Claude Code 2.1.218)

```
Usage: claude mcp add [options] <name> <commandOrUrl> [args...]
  -t, --transport <stdio|sse|http>   (по умолчанию stdio)
  -s, --scope <local|user|project>   (по умолчанию local)
  -e, --env KEY=value
```

Регистрация Codex как stdio-MCP:

```bash
claude mcp add codex -s user -- codex mcp-server
claude mcp list          # проверить: codex должен быть в списке
```

Это и делает `scripts/install-codex-plugin.sh` (идемпотентно, с проверкой наличия
`codex mcp-server`, опциями `--scope`/`--name`/`--remove`).

## Обязательное условие работы

MCP-сервер Codex сможет обращаться к модели, только если **Codex залогинен**:

```bash
codex login                                       # ChatGPT OAuth
printenv OPENAI_API_KEY | codex login --with-api-key   # или по ключу
```

Источники: [mcp-quickstart Claude Code](https://code.claude.com/docs/en/mcp-quickstart.md),
[Codex MCP docs](https://learn.chatgpt.com/docs/extend/mcp?surface=cli).

## Не путать направления

- `codex mcp-server` — Codex **является** сервером (его вызывает Claude Code). ← наш случай.
- `codex mcp add <name> -- <cmd>` — добавить внешние MCP-серверы **в** Codex (обратное направление).
