# Ресёрч: Telegram-плагин для Claude Code

> ⚠️ **Исправлено 2026-07-23.** Первая версия этого файла ошибочно утверждала, что
> официального Telegram-плагина нет. Это НЕВЕРНО: он есть в официальном маркетплейсе
> Anthropic —
> [telegram@claude-plugins-official](https://github.com/anthropics/claude-plugins-official/tree/main/external_plugins/telegram)
> (страница: [claude.com/plugins/telegram](https://claude.com/plugins/telegram)). Ниже — верные
> факты по его README; community-мосты оставлены как альтернатива.

## Официальный плагин (главный способ)

Плагин даёт Claude Code принимать/слать сообщения в Telegram, реагировать эмодзи, править
сообщения, получать фото, показывать «печатает…».

**Предусловие:** [Bun](https://bun.sh) (MCP-сервер плагина работает на Bun):
`curl -fsSL https://bun.sh/install | bash`.

**Установка + настройка** (слэш-команды в сессии Claude Code):
```
/plugin install telegram@claude-plugins-official
/reload-plugins
/telegram:configure <ТОКЕН-ОТ-BOTFATHER>      # пишет ~/.claude/channels/telegram/.env
```
Запуск с каналом:
```sh
claude --channels plugin:telegram@claude-plugins-official
```
Сопряжение и закрытие доступа:
```
# написать боту в Telegram → придёт 6-значный код →
/telegram:access pair <код>
/telegram:access policy allowlist       # ← ОБЯЗАТЕЛЬНО: по числовым user_id
```

**Через CLI (неинтерактивно — это делает `scripts/install-claude-telegram.sh`):**
```bash
claude plugin install telegram@claude-plugins-official -s user
# токен и сопряжение — уже в сессии (см. выше); скрипт токен не вписывает
```

> ✅ **Проверено вживую 2026-07-23** (Claude Code 2.1.218): скрипт поставил Bun 1.3.14 и
> `telegram@claude-plugins-official` **v0.0.6** (scope user, enabled); скиллы `configure` и
> `access` на месте. Дальше `/telegram:configure <токен>` и `/telegram:access policy allowlist`
> — уже в сессии (нужен реальный токен от @BotFather).

**🔒 Безопасность (из README):** политика по умолчанию — `pairing` (любой написавший боту
получит код сопряжения). **Сразу переводи в `allowlist`** по числовым `user_id`
(из [@userinfobot](https://t.me/userinfobot)). Токен бота — пароль: не в git/чат/логи, утёк →
`/revoke` у @BotFather. Бот = доступ к Claude Code на сервере.

## Альтернатива: community-мосты (неофициальные)

Если официальный плагин не подходит (напр. нужен полный контроль или мультиагентность), есть
зрелые сторонние мосты Telegram→Claude Code. Проверены через GitHub (⭐ на 07.2026):

| Репозиторий | Язык | ⭐ | Особенность |
|---|---|---|---|
| [RichardAtCT/claude-code-telegram](https://github.com/RichardAtCT/claude-code-telegram) | Python 3.11+ | ~2.7k | Agent SDK, allowlist + песочница `APPROVED_DIRECTORY`, MIT |
| [chenhg5/cc-connect](https://github.com/chenhg5/cc-connect) | Go | ~14.3k | long-polling без public IP, мульти-агент |
| [PleasePrompto/ductor](https://github.com/PleasePrompto/ductor) | Python 3.11+ | ~434 | `pipx install ductor`, двойной allowlist |

⚠️ Всё это **неофициально**; те же правила безопасности (allowlist по числовому user_id,
не `--dangerously-skip-permissions`, отдельный юзер). Не для прода без ревью.

## Telegram MCP-серверы (обратное направление)

Отдельная тема — чтобы Claude Code сам слал/читал Telegram (а не управлялся из него):
[chigwell/telegram-mcp](https://github.com/chigwell/telegram-mcp) (~1.3k, MTProto, личный
аккаунт), [areweai/tsgram-mcp](https://github.com/areweai/tsgram-mcp) (Bot API, безопаснее).
Подключаются через `claude mcp add`.

## Headless-запуск Claude Code (для самодельных мостов)

[code.claude.com/docs/en/headless](https://code.claude.com/docs/en/headless): `claude -p`,
`--output-format json|stream-json`, `--bare`, `--permission-mode dontAsk`, `--allowedTools`,
`--continue/--resume`. Плюс [Agent SDK](https://code.claude.com/docs/en/agent-sdk/overview).

**Вывод:** ставь **официальный плагин** (`scripts/install-claude-telegram.sh`); community-мосты
и MCP — только если нужен другой сценарий.
