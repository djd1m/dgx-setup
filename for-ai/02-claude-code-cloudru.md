# 02. Claude Code через Cloud.ru — рецепт для AI-кодера

**Цель:** подключить Claude Code к моделям Cloud.ru Foundation Models на DGX Spark / GB10 (aarch64, DGX OS) через прокси-переводчик LiteLLM.

---

## Критично — прочитать до первой команды

**1. Напрямую не работает. Не пытайся.** Несовпадение протоколов:

| | Формат | Эндпоинт |
|---|---|---|
| **Cloud.ru отдаёт** | OpenAI Chat Completions | `/v1/chat/completions` |
| **Claude Code понимает** | Anthropic Messages | `/v1/messages` |

Claude Code поддерживает ровно три формата — Anthropic Messages, Bedrock InvokeModel, Vertex rawPredict. **OpenAI Chat Completions в этом списке нет** — [gateway protocol reference](https://code.claude.com/docs/en/llm-gateway-protocol#api-formats).

`ANTHROPIC_BASE_URL=https://foundation-models.api.cloud.ru` → Claude Code шлёт Anthropic-запрос на `/v1/messages`, которого у Cloud.ru нет → **404**. Прослойка-переводчик **обязательна**.

> **NOT VERIFIED:** отсутствие `/v1/messages` у Cloud.ru выведено из молчания четырёх официальных страниц документации, а не из прямого заявления. Страница со спецификацией OpenAPI рендерится через JS и прочитать её не удалось — теоретически там мог бы обнаружиться недокументированный эндпоинт.

**2. Архитектура:**

```
Claude Code ──Anthropic /v1/messages──> LiteLLM ──OpenAI /chat/completions──> Cloud.ru
             ANTHROPIC_BASE_URL=          :4000                  foundation-models.api.cloud.ru/v1
             http://0.0.0.0:4000
```

LiteLLM принимает Anthropic-формат и переводит в OpenAI. Это официальная функция, а не хак: *«call all your LLM APIs in the Anthropic `v1/messages` format»* — [документация LiteLLM](https://docs.litellm.ai/docs/anthropic_unified/).

**3. Anthropic эту конфигурацию не поддерживает.** Дословно со [страницы про gateway](https://code.claude.com/docs/en/llm-gateway):

> doesn't endorse, maintain, or audit third-party gateway products, and doesn't support routing Claude Code to non-Claude models through any gateway

Работать может, но поломка — проблема пользователя, не Anthropic.

---

## Предусловия

Проверить всё до начала. Любой невыполненный пункт — стоп, см. `## Стоп-условия`.

| Проверка | Команда | Ожидаемо |
|---|---|---|
| Ключ Cloud.ru в окружении | `test -n "$CLOUD_RU_FM_API_KEY" && echo OK` | `OK` |
| Python + pip | `python3 -V && pip -V` | обе версии печатаются |
| Порт 4000 свободен | `ss -ltn '( sport = :4000 )'` | пустой список |
| Сеть до Cloud.ru | `curl -sI -o /dev/null -w '%{http_code}\n' https://foundation-models.api.cloud.ru/v1/models` | любой HTTP-код (не таймаут) |

Ключ выпускает **человек**, по [документации Cloud.ru](https://cloud.ru/docs/foundation-models/ug/topics/api-ref__authentication): сервисный аккаунт в личном кабинете → API-ключ → **Key ID** и **Key Secret**, срок жизни от 1 дня до 1 года. **Key Secret показывается один раз.** Для Foundation Models **не нужны** ни IAM-токен, ни project ID — только `Authorization: Bearer <ключ>`.

Ключ **никогда** не коммитить в git.

---

## Переменные

### Два разных ключа — не перепутать

Это **два разных credential'а**, и путаница между ними — основной режим отказа. Ключ Cloud.ru остаётся внутри LiteLLM (в конфиге, через `os.environ/CLOUD_RU_FM_API_KEY`) и наружу не выходит. `ANTHROPIC_AUTH_TOKEN` — это то, чем **Claude Code представляется твоему LiteLLM**.

```
Claude Code --[ANTHROPIC_AUTH_TOKEN]--> LiteLLM --[ключ Cloud.ru]--> Cloud.ru
```

| Ключ | Переменная | Кто кому предъявляет | Где живёт | Откуда взять |
|---|---|---|---|---|
| **Ключ Cloud.ru** | `CLOUD_RU_FM_API_KEY` | LiteLLM → Cloud.ru | только в `litellm-config.yaml` через `os.environ/CLOUD_RU_FM_API_KEY`; наружу не выходит | **только от человека**, не выдумывать |
| **Ключ LiteLLM** | `ANTHROPIC_AUTH_TOKEN` | Claude Code → LiteLLM | окружение Claude Code | **только от человека**; должен совпадать с тем, что LiteLLM настроен принимать |

`ANTHROPIC_AUTH_TOKEN` **не равен** `CLOUD_RU_FM_API_KEY`. Не подставлять один вместо другого.

Значение `ANTHROPIC_AUTH_TOKEN` должно совпадать с тем, что LiteLLM настроен принимать. Как именно настраивается авторизация на стороне LiteLLM — см. [его документацию](https://docs.litellm.ai/docs/anthropic_unified/); в официальном примере используется переменная `LITELLM_KEY`.

> **NOT VERIFIED:** принимает ли локально запущенный LiteLLM любое непустое значение, если мастер-ключ не задан, — не проверялось. **Не угадывать** — сверяться с документацией LiteLLM.

### Остальное

| Переменная | Значение | Откуда |
|---|---|---|
| `ANTHROPIC_BASE_URL` | `http://0.0.0.0:4000` | адрес LiteLLM |
| `ANTHROPIC_MODEL` | `cloudru-coder` | алиас из `litellm-config.yaml` |
| Модель на стороне Cloud.ru | `openai/Qwen/Qwen3-Coder-Next` | внутренняя, см. `## Выбор модели` |
| `api_base` | `https://foundation-models.api.cloud.ru/v1` | суффикс `/v1` обязателен, ничего сверх |
| Порт LiteLLM | `4000` | дефолт |

---

## Шаги

### Шаг 1. Проверить ключ отдельно от всего остального

**Команда:**
```bash
curl -s https://foundation-models.api.cloud.ru/v1/models \
  -H "Authorization: Bearer $CLOUD_RU_FM_API_KEY" | head -40
```

**Ожидаемый результат:** JSON со списком моделей.

**Если не так:**
- HTTP 401 / ошибка авторизации → ключ неверен или истёк. **Стоп**, запросить у человека новый. Не подбирать, не генерировать.
- Пустой ответ / таймаут → нет сети до Cloud.ru. **Стоп**, чинить сеть, дальше не идти.
- Дальше не двигаться, пока этот шаг не зелёный: все последующие ошибки будут маскироваться под ошибки LiteLLM.

### Шаг 2. Установить LiteLLM

**Команда:**
```bash
pip install 'litellm[proxy]'
```

**Ожидаемый результат:** установка завершается без ошибок, `litellm --version` печатает версию.

**Если не так:** `pip` ставит в системный Python и упирается в `externally-managed-environment` → создать venv (`python3 -m venv ~/.venvs/litellm && source ~/.venvs/litellm/bin/activate`) и повторить.

### Шаг 3. Написать конфиг

**Команда:**
```bash
cat > litellm-config.yaml <<'EOF'
model_list:
  - model_name: cloudru-coder
    litellm_params:
      model: openai/Qwen/Qwen3-Coder-Next
      api_base: https://foundation-models.api.cloud.ru/v1
      api_key: os.environ/CLOUD_RU_FM_API_KEY
EOF
```

**Ожидаемый результат:** файл создан, `api_key` — это литерал `os.environ/CLOUD_RU_FM_API_KEY`, а не подставленное значение ключа.

**Если не так / что не сломать:**
- ⚠️ **Суффикс `/v1` в `api_base` обязателен, и ничего сверх него.** Требование [документации LiteLLM](https://docs.litellm.ai/docs/providers/openai_compatible). Адрес Cloud.ru уже в нужном виде — **не дописывать** `/chat/completions`.
- Префикс `openai/` в поле `model` обязателен: он говорит LiteLLM «на той стороне OpenAI-совместимый API».
- Heredoc с `'EOF'` в кавычках — иначе шелл раскроет `$`-подстановку и впишет ключ в файл открытым текстом.

### Шаг 4. Запустить LiteLLM

**Команда:**
```bash
litellm --config litellm-config.yaml
```

Для unattended-исполнения запускать фоном и логировать, чтобы шаг 6 мог читать лог:
```bash
nohup litellm --config litellm-config.yaml > litellm.log 2>&1 &
```

**Ожидаемый результат:** поднимается на `http://0.0.0.0:4000`; `curl http://0.0.0.0:4000/health` отвечает.

**Если не так:**
- Порт занят → освободить 4000 или сменить порт и синхронно поменять `ANTHROPIC_BASE_URL`.
- Процесс упал сразу → читать `litellm.log`; типовая причина — `CLOUD_RU_FM_API_KEY` не виден процессу (запущен из другого окружения).

### Шаг 5. Направить Claude Code в LiteLLM

**Команда:**
```bash
export ANTHROPIC_BASE_URL=http://0.0.0.0:4000
export ANTHROPIC_AUTH_TOKEN=<ключ, который принимает твой LiteLLM>
export ANTHROPIC_MODEL=cloudru-coder
```

⚠️ `ANTHROPIC_AUTH_TOKEN` — это **не** ключ Cloud.ru. См. `## Переменные` → «Два разных ключа». Не подставлять сюда `$CLOUD_RU_FM_API_KEY`.

**Ожидаемый результат:** три переменные выставлены; `claude` запускается и отвечает.

**Если не так:**
- **401 и переменная взята правильная** → значение `ANTHROPIC_AUTH_TOKEN` не совпадает с тем, что LiteLLM настроен принимать. Сверить настройку авторизации по [документации LiteLLM](https://docs.litellm.ai/docs/anthropic_unified/) (в официальном примере — переменная `LITELLM_KEY`). **NOT VERIFIED:** принимает ли локально запущенный LiteLLM любое непустое значение без заданного мастер-ключа — не проверялось; **не угадывать**, читать документацию. Если из документации ответ не следует — **стоп**, спросить человека.
- **401** → почти наверняка взята не та переменная. Именно `ANTHROPIC_AUTH_TOKEN`, а не `ANTHROPIC_API_KEY`. Дословно из [документации](https://code.claude.com/docs/en/llm-gateway-connect):
  > Each variable sends the credential in a different HTTP header: `ANTHROPIC_AUTH_TOKEN` in `Authorization: Bearer`, `ANTHROPIC_API_KEY` in `x-api-key`

  LiteLLM ждёт `Authorization: Bearer`. Если в окружении остался `ANTHROPIC_API_KEY` — снять его: `unset ANTHROPIC_API_KEY`.
- **404** → `ANTHROPIC_BASE_URL` указывает на Cloud.ru напрямую, мимо LiteLLM. Вернуться к разделу «Критично».

### Шаг 6. Проверить сквозняк

**Команда:**
```bash
claude
```

**Ожидаемый результат:** агент отвечает; в `litellm.log` видно, что запросы уходят на Cloud.ru; агент реально читает файлы и запускает команды.

**Если не так:**
- **Самое вероятное место поломки — вызов инструментов.** Cloud.ru заявляет поддержку function calling у Qwen/GLM/gpt-oss, но агентный цикл Claude Code к этому очень требователен, а на пути стоит ещё и конвертация формата. **NOT VERIFIED** — вживую эта связка не тестировалась, ключа для проверки не было. Если инструменты не вызываются — это ожидаемый режим отказа, а не ошибка установки: зафиксировать факт и доложить человеку.
- Ошибки лимитов → **20 запросов в секунду и 20 параллельных на ключ**. Для одного человека с запасом.

---

## Выбор модели

Модели Cloud.ru делятся на два класса, разница принципиальная — [каталог моделей](https://cloud.ru/docs/foundation-models/ug/topics/overview__available__models).

| Класс | Модели | Данные | Брать? |
|---|---|---|---|
| **Внутренние** | `GigaChat`, `Qwen3-Coder-Next`, `Qwen3.5-397B-A17B`, `GLM-4.7`, `gpt-oss-120b`, `MiniMax-M2.5`, `bge-m3` | остаются в Cloud.ru, не покидают российскую инфраструктуру, запросы не логируются на стороне | **да, всегда** |
| **Внешние (не-Claude)** | `GPT-5`, `Gemini 3.x` | уходят наружу | нет |
| **Внешние Claude** | `claude-sonnet-4.6`, `claude-opus-4.6`, `claude-haiku-4.5` | уходят наружу | **никогда — см. ловушку** |

**Правило: по умолчанию всегда брать внутреннюю модель. Для кодинга — `Qwen3-Coder-Next`. Модели Claude через Cloud.ru не брать никогда, даже если о них попросили — сначала `## Стоп-условия`.**

### 🪤 Ловушка: не брать через Cloud.ru модели Claude

Соблазн очевиден: «настоящий Opus 4.6, да ещё и легально». Но получится **двойной перевод**:

```
Claude Code → [Anthropic] → LiteLLM → [OpenAI] → Cloud.ru → [Anthropic] → Claude
```

На среднем участке, где формат становится OpenAI-совместимым, **безвозвратно теряется** всё, что делает Claude Code хорошим: thinking-блоки, prompt caching, заголовки `anthropic-beta`, `context_management`, `output_config`. Полный список того, что зависит от сквозной передачи, — в [таблице feature pass-through](https://code.claude.com/docs/en/llm-gateway-protocol#feature-pass-through).

Платишь за Opus — получаешь его сильно урезанную версию.

И главное: **весь смысл Cloud.ru испаряется ровно на этих моделях.** Сюда идут за тем, чтобы данные остались в России, — а внешние модели их как раз отправляют наружу.

---

## Стоп-условия

Остановиться и спросить человека. Не обходить, не додумывать.

1. **Нет ключа — любого из двух.** **Никогда не выдумывать, не генерировать и не подставлять правдоподобные учётные данные.** Это относится к обоим ключам, и подставлять один вместо другого тоже нельзя:
   - `CLOUD_RU_FM_API_KEY` пуст или не прошёл шаг 1 → **стоп**, ключ выдаёт только человек.
   - `ANTHROPIC_AUTH_TOKEN` неизвестен → сначала выяснить по [документации LiteLLM](https://docs.litellm.ai/docs/anthropic_unified/), какое значение принимает локальный LiteLLM (в официальном примере — `LITELLM_KEY`). Если документация ответа не даёт — **стоп**, спросить человека. Не угадывать: принимает ли локальный LiteLLM любое непустое значение без мастер-ключа — **NOT VERIFIED**.
2. **Просят направить на внешние модели Claude** (`claude-sonnet-4.6`, `claude-opus-4.6`, `claude-haiku-4.5`) — **не выполнять сразу**. Объяснить: двойной перевод убивает thinking, prompt caching, `anthropic-beta`, `context_management`, `output_config`; данные уходят из Cloud.ru, что обнуляет весь смысл его использования. Предложить внутреннюю модель. Выполнять только после явного подтверждения человека.
3. **Шаг 1 не зелёный** — не ставить LiteLLM и не идти дальше.
4. **Стоимость и доступность с личного (не корпоративного) аккаунта — NOT VERIFIED.** Если человек рассчитывает на личный аккаунт — предупредить, что это не проверено.
5. **Тратить на это время в первую очередь не нужно.** Если у человека работает [01-claude-code-local.md](01-claude-code-local.md) — Claude Code на локальной Ollama, — то Cloud.ru даёт ровно одно преимущество: доступ к моделям, которые физически не влезают в GPU (например, `Qwen3.5-397B-A17B`).

| | Локальная Ollama | Cloud.ru + LiteLLM |
|---|---|---|
| Прослойки | нет | LiteLLM |
| Данные | не покидают DGX | уходят в Cloud.ru |
| Стоимость | 0 | по токенам |
| Размер моделей | ограничен памятью (на DGX Spark ~119 ГБ) | до 397B |
| Сложность | одна переменная | прокси + конфиг + ключ |

**Начинать с локальной. К Cloud.ru приходить, если упёрлись в размер модели.**

---

## Критерий готовности

Все пункты машинно-проверяемы. Красный пункт = не готово.

- [ ] Ключ валиден: команда ниже печатает список моделей
      ```bash
      curl -s https://foundation-models.api.cloud.ru/v1/models \
        -H "Authorization: Bearer $CLOUD_RU_FM_API_KEY" | head -40
      ```
- [ ] LiteLLM запущен: `curl -s -o /dev/null -w '%{http_code}\n' http://0.0.0.0:4000/health` отвечает
- [ ] Конфиг корректен: `grep -q 'api_base: https://foundation-models.api.cloud.ru/v1$' litellm-config.yaml` (суффикс `/v1`, ничего сверх)
- [ ] Модель внутренняя: `grep -q 'model: openai/Qwen/Qwen3-Coder-Next' litellm-config.yaml`
- [ ] Внешних Claude в конфиге нет: `! grep -qE 'claude-(sonnet|opus|haiku)' litellm-config.yaml`
- [ ] Переменные выставлены верно: `ANTHROPIC_AUTH_TOKEN` непустой, `ANTHROPIC_API_KEY` не выставлен, `ANTHROPIC_BASE_URL=http://0.0.0.0:4000`, `ANTHROPIC_MODEL=cloudru-coder`
      ```bash
      test -n "$ANTHROPIC_AUTH_TOKEN" && test -z "$ANTHROPIC_API_KEY" \
        && test "$ANTHROPIC_BASE_URL" = 'http://0.0.0.0:4000' \
        && test "$ANTHROPIC_MODEL" = 'cloudru-coder' && echo OK
      ```
- [ ] Ключи не перепутаны: `ANTHROPIC_AUTH_TOKEN` не равен ключу Cloud.ru
      ```bash
      test "$ANTHROPIC_AUTH_TOKEN" != "$CLOUD_RU_FM_API_KEY" && echo OK
      ```
- [ ] Ключ Cloud.ru не утёк в конфиг открытым текстом (лежит только как ссылка на переменную)
      ```bash
      grep -q 'api_key: os.environ/CLOUD_RU_FM_API_KEY' litellm-config.yaml \
        && ! grep -qF "$CLOUD_RU_FM_API_KEY" litellm-config.yaml && echo OK
      ```
- [ ] `claude` запускается и отвечает
- [ ] В логах LiteLLM видно, что запросы уходят на Cloud.ru: `grep -i 'foundation-models.api.cloud.ru' litellm.log`
- [ ] **Smoke-тест вызова инструментов** — агент реально читает файлы и запускает команды:
      ```bash
      echo 'canary-7f3a' > /tmp/tool-smoke.txt
      claude -p 'Прочитай /tmp/tool-smoke.txt и выведи его содержимое, затем выполни `uname -m` и выведи результат.'
      ```
      Готово, только если в ответе есть **и** `canary-7f3a` (сработал файловый инструмент), **и** фактический вывод `uname -m` — на DGX Spark это **`aarch64`**, на классическом x86-DGX `x86_64` (сработал запуск команд). Сверять с реальным `uname -m` машины, а не с ожиданием. Ответ без вызова инструментов — не зачёт: это ровно тот отказ, который описан в шаге 6 и помечен **NOT VERIFIED**.
