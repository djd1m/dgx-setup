# 14. Claude Code через Cloud.ru FM НАПРЯМУЮ (Anthropic API, без LiteLLM) — рецепт

**Цель:** подключить Claude Code к Cloud.ru Foundation Models через их **Anthropic-совместимый
`/v1/messages`** — без LiteLLM, без docker, без туннеля. Команда запуска — `claude-fm`.

> Это **не** [02-claude-code-cloudru.md](02-claude-code-cloudru.md). Там LiteLLM-переводчик, потому
> что на момент написания у Cloud.ru не было `/v1/messages`. **Проверено живым запросом 2026-07-24:
> теперь `/v1/messages` ЕСТЬ** → Claude Code ходит напрямую. 02 оставлен как есть (путь через LiteLLM).

> ⚠️ **Эндпоинт РАБОТАЕТ, но НЕ задокументирован (важно).** В официальной документации Cloud.ru
> `/v1/messages` **нет** — описан только OpenAI `/v1/chat/completions`
> ([api-ref](https://cloud.ru/docs/foundation-models/ug/topics/api-ref.html),
> [quickstart](https://cloud.ru/docs/foundation-models/ug/topics/quickstart.html)). Работоспособность
> `/v1/messages` установлена **только живым запросом** (2026-07-24). Следствие: недокументированный
> эндпоинт Cloud.ru может изменить/убрать без предупреждения, официальной поддержки нет. Если однажды
> начнёт отдавать 404 — откат на документированный путь через LiteLLM: [02-claude-code-cloudru.md](02-claude-code-cloudru.md).

## Что проверено вживую (2026-07-24)

- `POST https://foundation-models.api.cloud.ru/v1/messages` отвечает в **Anthropic-формате**
  (не 404). Авторизация — `Authorization: Bearer <ключ Cloud.ru>`.
- Claude Code: `ANTHROPIC_BASE_URL=https://foundation-models.api.cloud.ru` (сам добавит `/v1/messages`),
  `ANTHROPIC_AUTH_TOKEN=<ключ Cloud.ru>`, `ANTHROPIC_MODEL=<id>`. `ANTHROPIC_API_KEY` **снять**
  (иначе уйдёт `x-api-key` вместо Bearer).

## Доступность моделей по `/v1/messages` (проверено)

| id | Anthropic API | Класс |
|---|---|---|
| `deepseek-ai/DeepSeek-V4-Pro` | ✅ 200 | внутр. (РФ), сильная агентная — **дефолт** |
| `deepseek/deepseek-v3.2`, `deepseek-ai/DeepSeek-V3.1-Terminus` | ✅ 200 | внутр. |
| `moonshotai/Kimi-K2.6`, `kimi-k2.5`, `kimi-k2-thinking` | ✅ 200 | внутр. |
| `Qwen/Qwen3.5-397B-A17B` | ✅ 200 | внутр. |
| `MiniMaxAI/MiniMax-M3`, `MiniMax-M2.5` | ✅ 200 | внутр. |
| `zai-org/GLM-5.2`, `GLM-4.7`, `z-ai/glm-4.6` | ✅ 200 | внутр. |
| `xiaomi/mimo-v2.5-pro`, `meituan-longcat/LongCat-Flash-Chat` | ✅ 200 | внутр. |
| `anthropic/claude-haiku-4.5` (и др. `anthropic/claude-*`) | ✅ 200 | **ВНЕШН.** — настоящий Claude, данные уходят из РФ, платно дороже |
| `Qwen/Qwen3.6-35B-A3B` | ❌ 403 | не подключена к проекту (на OpenAI-эндпоинте работает, на Anthropic — нет; подключается в консоли Cloud.ru) |
| `claude-haiku-4.5` (без префикса `anthropic/`) | ❌ 404 | нужен префикс |

🛑 **id всегда из `/v1/models`, регистр важен.** Не с HF-карточки.

## Установка — одним скриптом

```bash
git clone https://github.com/djd1m/dgx-setup.git && cd dgx-setup   # если ещё нет
bash scripts/install-claude-fm.sh                         # спросит ключ, подберёт модель, создаст claude-fm
bash scripts/install-claude-fm.sh --model moonshotai/Kimi-K2.6    # выбрать конкретную
bash scripts/install-claude-fm.sh --diagnose              # только проверка эндпоинта/моделей
```

Скрипт: проверяет ключ (`/v1/models`), проверяет `/v1/messages` и **подбирает рабочую модель**
(перебор `DeepSeek-V4-Pro → V3.1-Terminus → claude-haiku-4.5`), пишет ключ+модель в
`~/.dgx-claude/cloudru-fm.env` (chmod 600) и создаёт обёртку `~/.local/bin/claude-fm`.

## Обёртка `claude-fm` (что внутри)

```bash
set -a; . ~/.dgx-claude/cloudru-fm.env; set +a
export ANTHROPIC_BASE_URL="https://foundation-models.api.cloud.ru"
export ANTHROPIC_AUTH_TOKEN="$CLOUD_RU_FM_API_KEY"
export ANTHROPIC_MODEL="${CLAUDE_FM_MODEL:-deepseek-ai/DeepSeek-V4-Pro}"
unset ANTHROPIC_API_KEY
exec claude "$@"
```

Ключ Cloud.ru — только в `cloudru-fm.env` (600), в обёртку/git/чат не попадает.

## Стоп-условия

1. **Ключ Cloud.ru — секрет.** Выдаёт человек. Никогда не выдумывать. Только в `.env` (600), не в git/логи/чат.
2. **Внешние `anthropic/claude-*` — только по явной просьбе.** Данные уходят из РФ, дороже, и обнуляют
   смысл Cloud.ru (данные в России). По умолчанию — внутренняя модель.
3. **`Qwen/Qwen3.6-35B-A3B` на Anthropic-эндпоинте = 403.** Не подставлять её в `claude-fm`; либо
   подключить к проекту в консоли Cloud.ru, либо взять другую (✅ выше).
4. **Вызов инструментов на не-Claude модели — NOT VERIFIED для полного агентного цикла.** Базовые
   ответы приходят (проверено), но агентный tool-loop Claude Code требователен. Смоук-тест обязателен.

## Критерий готовности

```bash
command -v claude-fm >/dev/null && echo WRAPPER_OK
claude-fm -p 'скажи привет одним словом по-русски'          # приходит ответ
# смоук-тест инструментов (главный критерий):
echo 'canary-7f3a' > /tmp/fm-smoke.txt
claude-fm -p 'прочитай /tmp/fm-smoke.txt дословно и выполни uname -m'
```
Готово, только если в ответе есть **и** `canary-7f3a` (файловый инструмент), **и** `aarch64`
(запуск команд). Ответ без вызова инструментов — не зачёт (см. стоп-условие 4).
