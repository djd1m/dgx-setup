# Ресёрг: Telegram <-> Claude Code (мосты, MCP, headless)

> Верифицировано через GitHub API + чтение README + доки Claude Code (2026-07-23).
> Основа для `scripts/install-claude-telegram.sh`. Все репозитории реально существуют
> (открывались на момент проверки). ⭐ приблизительны на 07.2026.

## Главное

**Официального Telegram-плагина для Claude Code НЕ существует.** Официальный путь запускать
Claude Code программно — headless (`claude -p`) и Agent SDK
([code.claude.com/docs/en/headless](https://code.claude.com/docs/en/headless)). Всё ниже —
**неофициальные** community-мосты.

## (a) Готовые мосты Telegram → Claude Code (управлять Claude из Telegram)

| Репозиторий | Язык | ⭐ | Как дёргает Claude | Безопасность | Зрелость |
|---|---|---|---|---|---|
| [RichardAtCT/claude-code-telegram](https://github.com/RichardAtCT/claude-code-telegram) | Python 3.11+ | ~2.7k | Agent SDK + CLI fallback | allowlist `ALLOWED_USERS`, песочница `APPROVED_DIRECTORY`, anti-path-traversal, rate-limit, аудит | **самый зрелый**, MIT, `uv tool install git+…` |
| [PleasePrompto/ductor](https://github.com/PleasePrompto/ductor) | Python 3.11+ | ~434 | `claude` CLI как subprocess | двойной allowlist (user+group) | активный, `pipx install ductor` |
| [chenhg5/cc-connect](https://github.com/chenhg5/cc-connect) | Go | ~14.3k | мост, long-polling (без public IP) | OS-user изоляция, permission-modes | популярен, мульти-агент, npm/brew/binary |
| [op7418/Claude-to-IM](https://github.com/op7418/Claude-to-IM) | TS | ~474 | оборачивает Claude Code SDK | rate-limit, whitelist | это **библиотека**, не готовый бот |
| [six-ddc/ccbot](https://github.com/six-ddc/ccbot) | Python | ~266 | tmux-мост (keystrokes) | allowlist user_id | активный |

⚠️ **Не для прода:** [hanxiao/claudecode-telegram](https://github.com/hanxiao/claudecode-telegram)
и подобные tmux-мосты запускают `claude --dangerously-skip-permissions` — снимают ВСЕ
подтверждения. Только для личного эксперимента.

**Выбор для скрипта:** `RichardAtCT/claude-code-telegram` — встроенные allowlist + песочница
каталога, Agent SDK, MIT. Установка: `uv tool install git+https://github.com/RichardAtCT/claude-code-telegram@<тег>`,
затем `.env` (`TELEGRAM_BOT_TOKEN`, `TELEGRAM_BOT_USERNAME`, `ALLOWED_USERS`, `APPROVED_DIRECTORY`),
запуск `make run`. Python 3.11+.

## (b) Telegram MCP-серверы (обратное: Claude управляет Telegram)

Это НЕ про «управлять Claude из Telegram», а про то, чтобы Claude Code слал/читал Telegram.
Подключаются через `claude mcp add`.

| Репозиторий | ⭐ | Транспорт | Bot API vs аккаунт |
|---|---|---|---|
| [chigwell/telegram-mcp](https://github.com/chigwell/telegram-mcp) | ~1.3k | stdio/http/sse | MTProto (**личный аккаунт**, 80+ инструментов) |
| [areweai/tsgram-mcp](https://github.com/areweai/tsgram-mcp) | ~92 | stdio | **Bot API** (безопаснее, заточен под Claude Code) |
| [qpd-v/mcp-communicator-telegram](https://github.com/qpd-v/mcp-communicator-telegram) | ~45 | stdio | Bot API (ask-user, уведомления) |

⚠️ MTProto-серверы действуют от лица **личного аккаунта** (доступ ко всем чатам) — рискованнее,
чем Bot-API.

## (c) Headless-запуск Claude Code (официальные доки)

[code.claude.com/docs/en/headless](https://code.claude.com/docs/en/headless),
[Agent SDK](https://code.claude.com/docs/en/agent-sdk/overview):

- `claude -p "<prompt>"` — неинтерактивно, stdin→stdout.
- `--output-format text|json|stream-json` (`json` → `.result`, `session_id`, `total_cost_usd`;
  `stream-json` → построчный стрим для «печатает…»).
- `--allowedTools "Read,Edit,Bash"` — авто-одобрение конкретных инструментов.
- `--permission-mode dontAsk|acceptEdits` — `dontAsk` максимально закрыт (для бота/CI).
- `--bare` — без авто-подхвата hooks/skills/MCP/CLAUDE.md (воспроизводимо; скоро дефолт для `-p`).
- `--continue`/`--resume <session_id>` — персистентная сессия на чат.

## (d) Безопасность (обязательно)

Бот с доступом к Claude Code = фактически **удалённый shell** на сервере.
- **allowlist по числовому `user_id`** (не username — подделывается); остальных отклонять.
- **НЕ** использовать `--dangerously-skip-permissions`; ограничивать `--allowedTools`/`--permission-mode dontAsk`.
- запускать от **отдельного непривилегированного пользователя**, узкий `APPROVED_DIRECTORY` (не `$HOME`, не `/`).
- токен бота и ключи — в `.env` (chmod 600), не в git/чат/логи; включить rate-limit.
- long-polling (cc-connect/ductor) не требует открывать порт — безопаснее webhook.

## Минимальный самодельный мост (если не хочется чужого кода)

```
python-telegram-bot  ->  if update.effective_user.id in ALLOWED_IDS
                     ->  subprocess: claude --bare -p "<текст>" --output-format json
                                     --permission-mode dontAsk --allowedTools "Read,Edit,Bash"
                     ->  parse .result  ->  reply
```
~50 строк, но всю безопасность (allowlist, ограничение инструментов, отдельный юзер, таймауты)
делаешь сам. Помечено как **самодельное**, не готовый проект.
