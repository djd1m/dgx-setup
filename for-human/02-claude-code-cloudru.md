# 02. Claude Code через Cloud.ru Foundation Models

Cloud.ru Foundation Models — российский сервис, дающий доступ к ~20 моделям по единому API.
Здесь нужен, если модели мощнее того, что тянет твой DGX, а данные при этом должны остаться
в России.

---

## Сразу главное: напрямую это не работает

Не трать время на попытки. Причина — **несовпадение протоколов**, подтверждённое
документацией с обеих сторон:

| | Формат | Эндпоинт |
|---|---|---|
| **Cloud.ru отдаёт** | OpenAI Chat Completions | `/v1/chat/completions` |
| **Claude Code понимает** | Anthropic Messages | `/v1/messages` |

Claude Code поддерживает ровно три формата — Anthropic Messages, Bedrock InvokeModel,
Vertex rawPredict. **OpenAI Chat Completions в этом списке нет** —
[gateway protocol reference](https://code.claude.com/docs/en/llm-gateway-protocol#api-formats).

Если просто указать `ANTHROPIC_BASE_URL=https://foundation-models.api.cloud.ru`, Claude Code
пошлёт запрос в формате Anthropic на `/v1/messages`, которого у Cloud.ru нет, и получит **404**.

**Нужна прослойка-переводчик.** Дальше — про неё.

**Проверено по спецификации, а не по умолчанию документации.** Раньше здесь стоял
`NOT VERIFIED`: страница OpenAPI рендерится через JS и не читалась. Но у Cloud.ru есть
**скачиваемый статический YAML** со спецификацией — и она сама себя называет
«ограниченной двумя методами». В объекте `paths` ровно два элемента:

| Метод | Endpoint |
|---|---|
| `GET` | `/v1/models` |
| `POST` | `/v1/chat/completions` |

**`/v1/messages` там нет.** Официальный quickstart Cloud.ru это подтверждает с другой
стороны: он показывает вызов через OpenAI SDK методом `client.chat.completions.create`.

> Граница вывода: это доказывает отсутствие `/v1/messages` **в опубликованной спецификации**
> на дату проверки. Скрытый недокументированный эндпоинт формально не исключён — но
> строить на нём инструкцию нельзя.

---

## Архитектура

```
Claude Code ──Anthropic /v1/messages──> LiteLLM ──OpenAI /chat/completions──> Cloud.ru
             ANTHROPIC_BASE_URL=          :4000                  foundation-models.api.cloud.ru/v1
             http://0.0.0.0:4000
```

**LiteLLM** — прокси, который умеет принимать запросы в формате Anthropic и переводить их
в OpenAI. Это его официальная функция, а не хак: *«call all your LLM APIs in the Anthropic
`v1/messages` format»* — [документация LiteLLM](https://docs.litellm.ai/docs/anthropic_unified/).

---

## Шаг 1. Получить ключ Cloud.ru

По [документации Cloud.ru](https://cloud.ru/docs/foundation-models/ug/topics/api-ref__authentication):

1. Создай сервисный аккаунт в личном кабинете.
2. Выпусти для него API-ключ — получишь **Key ID** и **Key Secret**.
3. Срок жизни ключа — от 1 дня до 1 года.

> ⚠️ **Key Secret показывается один раз.** Не закроешь окно, не записав — придётся выпускать заново.

Приятная деталь: для Foundation Models **не нужны** ни IAM-токен, ни project ID — только
`Authorization: Bearer <ключ>`. Это проще, чем у большинства сервисов Cloud.ru.

Сохрани ключ в переменную (и **никогда** не коммить его в git):

```bash
export CLOUD_RU_FM_API_KEY='твой-ключ'
```

---

## Шаг 2. Выбрать модель — и не попасться в ловушку

Модели Cloud.ru делятся на два класса, и разница принципиальная —
[каталог моделей](https://cloud.ru/docs/foundation-models/ug/topics/overview__available__models):

### Внутренние — данные остаются в Cloud.ru

`GigaChat`, `Qwen3-Coder-Next`, `Qwen3.5-397B-A17B`, `GLM-4.7`, `gpt-oss-120b`,
`MiniMax-M2.5`, `bge-m3`.

**Это и есть честный сценарий использования Cloud.ru.** Данные не покидают российскую
инфраструктуру, запросы не логируются на стороне. Ради этого сюда и идут.

### Внешние — данные уходят наружу

`GPT-5`, `Gemini 3.x`, **и Claude — `claude-sonnet-4.6`, `claude-opus-4.6`, `claude-haiku-4.5`**.

### 🪤 Ловушка: не бери через Cloud.ru модели Claude

Соблазн очевиден: «настоящий Opus 4.6, да ещё и легально». Но получится **двойной перевод**:

```
Claude Code → [Anthropic] → LiteLLM → [OpenAI] → Cloud.ru → [Anthropic] → Claude
```

На среднем участке, где формат становится OpenAI-совместимым, **безвозвратно теряется**
всё, что делает Claude Code хорошим: thinking-блоки, prompt caching, заголовки `anthropic-beta`,
`context_management`, `output_config`. Полный список того, что зависит от сквозной передачи, —
в [таблице feature pass-through](https://code.claude.com/docs/en/llm-gateway-protocol#feature-pass-through).

Ты платишь за Opus, а получаешь его сильно урезанную версию.

И главное: **весь смысл Cloud.ru испаряется ровно на этих моделях.** Ты шёл сюда за тем,
чтобы данные остались в России, — а внешние модели их как раз отправляют наружу.

**Вывод: бери внутренние модели.** Например, `Qwen3-Coder-Next` для кодинга.

---

## Шаг 3. Поднять LiteLLM

```bash
pip install 'litellm[proxy]'
```

Создай `litellm-config.yaml`:

```yaml
model_list:
  - model_name: cloudru-coder
    litellm_params:
      model: openai/Qwen/Qwen3-Coder-Next
      api_base: https://foundation-models.api.cloud.ru/v1
      api_key: os.environ/CLOUD_RU_FM_API_KEY
```

> ⚠️ **Суффикс `/v1` в `api_base` обязателен, и ничего сверх него.** Это требование
> [документации LiteLLM](https://docs.litellm.ai/docs/providers/openai_compatible).
> Адрес Cloud.ru уже в нужном виде — не дописывай `/chat/completions`.

Префикс `openai/` в поле `model` говорит LiteLLM: «на той стороне OpenAI-совместимый API».

Запусти:

```bash
litellm --config litellm-config.yaml
```

Поднимется на `http://0.0.0.0:4000`.

---

## Шаг 4. Направить Claude Code в LiteLLM

```bash
export ANTHROPIC_BASE_URL=http://0.0.0.0:4000
export ANTHROPIC_AUTH_TOKEN=<ключ, который принимает твой LiteLLM>
export ANTHROPIC_MODEL=cloudru-coder
```

### Что за «ключ LiteLLM» и откуда он берётся

Важно не перепутать: это **не** ключ Cloud.ru. Ключ Cloud.ru остаётся внутри LiteLLM
(в конфиге, через `os.environ/CLOUD_RU_FM_API_KEY`) и наружу не выходит. А
`ANTHROPIC_AUTH_TOKEN` — это то, чем **Claude Code представляется твоему LiteLLM**.

```
Claude Code --[ANTHROPIC_AUTH_TOKEN]--> LiteLLM --[ключ Cloud.ru]--> Cloud.ru
```

Значение должно совпадать с тем, что LiteLLM настроен принимать. Как именно настраивается
авторизация на стороне LiteLLM — смотри в [его документации](https://docs.litellm.ai/docs/anthropic_unified/);
в официальном примере используется переменная `LITELLM_KEY`.

### Если `master_key` не задан — проверки ключа нет вовсе

Раньше здесь стоял `NOT VERIFIED`. **Теперь проверено.**

Документация LiteLLM помечает `general_settings.master_key` как **OPTIONAL**: он нужен,
только если ты хочешь **требовать** ключ во всех вызовах. В коде LiteLLM ветка
`master_key is None` пропускает запрос независимо от того, прислан ли `api_key` — сам
комментарий в коде называет это **«No-auth dev mode»**.

Практически это значит: на локальном LiteLLM без `master_key` можно вообще не слать
`Authorization` — заработает. Значение `ANTHROPIC_AUTH_TOKEN` в этом режиме ни на что
не влияет.

⚠️ **И важная деталь, снимающая частое заблуждение:** твой `Authorization` **не превращается
в ключ провайдера**. Функция `clean_headers` в LiteLLM **вырезает** клиентский заголовок
перед вызовом Cloud.ru. Credential провайдера берётся только из конфига. Так что подставить
ключ Cloud.ru в `ANTHROPIC_AUTH_TOKEN` и надеяться, что он «пройдёт насквозь», — не выйдет.

Вывод относится к стандартному режиму. Включённые JWT/OAuth2 или свои auth-хуки меняют картину.

Именно `ANTHROPIC_AUTH_TOKEN`, а не `ANTHROPIC_API_KEY` — разница в том, каким заголовком
уходит ключ. Дословно из [документации](https://code.claude.com/docs/en/llm-gateway-connect):

> Each variable sends the credential in a different HTTP header: `ANTHROPIC_AUTH_TOKEN`
> in `Authorization: Bearer`, `ANTHROPIC_API_KEY` in `x-api-key`

LiteLLM ждёт `Authorization: Bearer`. Возьмёшь не ту переменную — получишь 401.

Запуск:

```bash
claude
```

---

## Что нужно знать до того, как вкладываться

**1. Anthropic эту конфигурацию не поддерживает.** Дословно со [страницы про gateway](https://code.claude.com/docs/en/llm-gateway):

> doesn't endorse, maintain, or audit third-party gateway products, and doesn't support
> routing Claude Code to non-Claude models through any gateway

То есть работать может, но если сломается — это твоя проблема, не их.

**2. Самое вероятное место поломки — вызов инструментов.** Cloud.ru заявляет поддержку
function calling у Qwen/GLM/gpt-oss, но агентный цикл Claude Code к этому очень требователен,
а на пути стоит ещё и конвертация формата. **NOT VERIFIED** — вживую эта связка не тестировалась,
ключа для проверки не было.

**3. Лимит: 20 запросов в секунду и 20 параллельных на ключ.** Для одного человека с запасом.

**4. Личный аккаунт и цена — проверено частично.**

Цена `Qwen/Qwen3-Coder-Next` на дату проверки (17 июля 2026) по официальному каталогу
Cloud.ru: **122 ₽ за 1 млн входных токенов** и **244 ₽ за 1 млн генерируемых**.

Регистрация физлица подтверждена: Cloud.ru Evolution разрешает регистрацию физических лиц,
**все аккаунты по умолчанию имеют тип «Физлицо»**, оплата с положительного баланса
допускается. Для стандартной регистрации нужен **российский номер телефона**.

> **NOT VERIFIED:** прямого обещания, что **именно Foundation Models** доступен аккаунту
> типа «Физлицо», в документации нет. При этом Cloud.ru прямо предупреждает, что
> **тип аккаунта влияет на доступность платформ и сервисов**. То есть аккаунт создать
> можно и цена известна — но гарантии доступа к этому конкретному сервису физлицу нет.
> Выяснится на первом же запросе.

---

## Когда это вообще нужно

Честно говоря — **не в первую очередь**. Если у тебя работает [01-claude-code-local.md](01-claude-code-local.md),
то есть Claude Code на локальной Ollama, то Cloud.ru даёт только одно преимущество:
доступ к моделям, которые физически не влезают в твои GPU (например, `Qwen3.5-397B-A17B`).

| | Локальная Ollama | Cloud.ru + LiteLLM |
|---|---|---|
| Прослойки | нет | LiteLLM |
| Данные | не покидают DGX | уходят в Cloud.ru |
| Стоимость | 0 | по токенам |
| Размер моделей | ограничен памятью (на DGX Spark ~119 ГБ) | до 397B |
| Сложность | одна переменная | прокси + конфиг + ключ |

**Начни с локальной. К Cloud.ru приходи, если упрёшься в размер модели.**

---

## Готово, если

- [ ] `curl` с ключом на `https://foundation-models.api.cloud.ru/v1/models` отдаёт список моделей
- [ ] LiteLLM запущен, `curl http://0.0.0.0:4000/health` отвечает
- [ ] `claude` запускается и отвечает
- [ ] в логах LiteLLM видно, что запросы уходят на Cloud.ru
- [ ] агент реально читает файлы и запускает команды (проверка вызова инструментов)

Проверка ключа отдельно от всего остального:

```bash
curl -s https://foundation-models.api.cloud.ru/v1/models \
  -H "Authorization: Bearer $CLOUD_RU_FM_API_KEY" | head -40
```
