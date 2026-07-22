# 12. Облачный мозг Cloud.ru и маршрутизация моделей — рецепт для AI-кодера

Цель: подключить сильную облачную FM Cloud.ru как **мозг агента** (OpenAI-совместимый эндпоинт),
локальные модели на [Ollama](00-ollama.md) — как fallback и вспомогательные роли. Пользователь
русскоязычный → выбор модели идёт по **двум осям сразу**: tool-calling **и** подтверждённый русский.

Эндпоинт Cloud.ru (публичный): `https://foundation-models.api.cloud.ru/v1`.
Точный id модели — **только из `/v1/models`**, не угадывать.

> Все факты — по инлайн-источникам. Точные id моделей Cloud.ru подтверждены живым `/v1/models`
> от 2026-07-22. Непроверенное — **NOT VERIFIED**. Не добавлять непроверенных утверждений.

---

## Предусловия

| Проверка | Ожидаемо | Если не так |
|---|---|---|
| Ollama поднята ([00-ollama.md](00-ollama.md)) | `curl localhost:11434/api/tags` → JSON | сначала 00 |
| Есть ключ Cloud.ru | лежит в `.env`, не в git | **STOP** — взять у человека, не хардкодить |
| Известен целевой агент | Hermes / OpenClaw / Ouroboros | без этого механизм fallback не выбрать |
| Пользователь русскоязычный | да | → мозговая модель обязана иметь **подтверждённый русский** |

**Правило выбора (не нарушать): две независимые оси.**
1. tool-calling (структурный `tool_calls`, не текст; не ломается на многоходовых);
2. русский **назван поимённо** в источнике (не «сильная мультиязычность вообще»).

---

## Переменные

| Переменная | Как получить | Формат / пример |
|---|---|---|
| `CLOUDRU_BASE_URL` | публичный адрес сервиса | `https://foundation-models.api.cloud.ru/v1` |
| `CLOUDRU_API_KEY` | у человека → **только `.env`** | секрет, не в git/логи/чат |
| `CLOUD_MODEL_ID` | **из `curl $CLOUDRU_BASE_URL/models`** | не угадывать; напр. `Qwen/Qwen3-235B-A22B-Instruct-2507` |
| `OLLAMA_LOCAL_URL` | по агенту (см. Шаг 3) | Hermes/Ouroboros: `.../v1`; OpenClaw: **без** `/v1` |
| `AUX_MODEL` | дешёвая локальная | `gpt-oss-20b` (58 tok/s) |

---

## Шаги

### Шаг 1. Выбрать мозговую модель (по двум осям)

**По умолчанию — `Qwen/Qwen3-235B-A22B-Instruct-2507`.** Единственный кандидат YES/YES:
- tool-calling измерен: BFCL-v3 **70.9**, TAU2-Retail **74.6** —
  [карточка](https://huggingface.co/Qwen/Qwen3-235B-A22B-Instruct-2507);
- русский назван поимённо (119 языков) — [блог Qwen3](https://qwenlm.github.io/blog/qwen3/),
  [tech report](https://arxiv.org/abs/2505.09388).

**Запасной — `Qwen/Qwen3-30B-A3B-Instruct-2507`:** тот же русский
([блог Qwen3](https://qwenlm.github.io/blog/qwen3/)), tool-calling слабее (BFCL-v3 **65.1**,
TAU2-Retail **57.0**, проседает Telecom 12.3 / Airline 38) —
[карточка](https://huggingface.co/Qwen/Qwen3-30B-A3B-Instruct-2507). **Тот же hermes-парсер,
что у 235B** → миграция лёгкая.

🛑 **Не брать мозгом:**
- **Qwen3.5-397B-A17B** — tool чуть выше (BFCL-V4 72.9, TAU2 86.7,
  [карточка](https://huggingface.co/Qwen/Qwen3.5-397B-A17B)), но русский **не назван**
  (только «201 language»), числа vendor-only 2026 без воспроизведения. **NOT VERIFIED: русский у 397B.**
- **Kimi K2.6** — задокументированные дегенеративные циклы в tool-use:
  [vLLM](https://vllm.ai/blog/2025-10-28-kimi-k2-accuracy),
  [Zed #51180](https://github.com/zed-industries/zed/issues/51180),
  [форум NVIDIA](https://forums.developer.nvidia.com/t/bug-https-build-nvidia-com-moonshotai-kimi-k2-6-kimi-k2-6-enters-infinite-repetition-loop-spamming-when-thinking/368740).
  Русский тоже не подтверждён.

### Шаг 2. (Опц.) Per-task маппинг локальных ролей

Если роли разделяются, а не одна модель. Замеры tok/s —
[официальные DGX Spark](https://ollama.com/blog/nvidia-spark-performance).

| Роль | Модель | Источник |
|---|---|---|
| Оркестратор + рассуждения | `gpt-oss-120b` (MoE, 41 tok/s) | [ollama](https://ollama.com/library/gpt-oss) · [OpenAI](https://openai.com/index/introducing-gpt-oss/) |
| Быстрый ход / роутинг | `gpt-oss-20b` (58 tok/s) | — |
| Агентное кодирование | `Qwen3-Coder-30B-A3B` (non-thinking) | [HF](https://huggingface.co/Qwen/Qwen3-Coder-30B-A3B-Instruct) |
| Рассуждения на скорости MoE | `Qwen3-30B-A3B-Thinking-2507` | [HF](https://huggingface.co/Qwen/Qwen3-30B-A3B-Thinking-2507) |
| Vision | `Qwen3-VL-30B` | [ollama](https://ollama.com/library/qwen3-vl) |

🛑 **Русский финальный ответ — не через gpt-oss** (русский не подтверждён, Шаг 4). gpt-oss
оркестрирует, отвечает пользователю модель с подтверждённым русским.

### Шаг 3. Настроить fallback у своего агента

**Hermes** ([fallback-providers.md](https://raw.githubusercontent.com/NousResearch/hermes-agent/main/website/docs/user-guide/features/fallback-providers.md),
[providers.md](https://github.com/NousResearch/hermes-agent/blob/main/website/docs/integrations/providers.md)):
- `~/.hermes/config.yaml` → `fallback_providers:` списком `{provider, model, base_url, key_env}`;
  команды `hermes fallback add/list`.
- Вспомогательное — `auxiliary.<task>.provider/model` (сюда `AUX_MODEL`).
- Локальный: `provider: custom`, `base_url: http://localhost:11434/v1`.

**OpenClaw** ([models.md](https://raw.githubusercontent.com/openclaw/openclaw/main/docs/concepts/models.md),
[ollama.md](https://raw.githubusercontent.com/openclaw/openclaw/main/docs/providers/ollama.md)):
- `agents.defaults.model.fallbacks` — список, перебор по порядку.
- `agents.entries.*.model` — per-agent, **строгий без fallback** пока нет своего списка.
- `utilityModel` — служебка.
- 🛑 **Ollama через `/api/chat`, БЕЗ `/v1`** — иначе ломается вызов инструментов.

**Ouroboros** ([README](https://raw.githubusercontent.com/razzant/ouroboros/main/README.md)):
- Слоты env: `OUROBOROS_MODEL` (Main), `OUROBOROS_MODEL_HEAVY`, `OUROBOROS_MODEL_LIGHT`,
  `OUROBOROS_MODEL_VISION`; кросс-fallback `OUROBOROS_MODEL_FALLBACKS`.
- Локальный эндпоинт — тип провайдера **openai-compatible**.
- Маппинг: Main→gpt-oss-120b, Heavy→Thinking, Light→gpt-oss-20b, Vision→Qwen3-VL.

### Шаг 4. Свериться с таблицей русского (перед финализацией мозга)

| Русский | Модель | Источник |
|---|---|---|
| ✅ поимённо | Qwen3-Instruct (119 языков) | [блог Qwen3](https://qwenlm.github.io/blog/qwen3/) |
| ✅ поимённо | Qwen3.5 («ru \| Russian») | [Alibaba Cloud](https://www.alibabacloud.com/help/en/model-studio/qwen3-5-livetranslate-flash-realtime) |
| ✅ измерен | DeepSeek-V3.1-Terminus (MMLU-ProX RU 74.9) | [arxiv](https://arxiv.org/abs/2503.10497) |
| ✅ нативный, ~234 tok/s | gigachat-3-lightning (Sber, MMLU-RU 0.68) | [HF](https://huggingface.co/ai-sage/GigaChat3-10B-A1.8B) |
| ❌ нет | gpt-oss (нет в MMMLU) | [arxiv](https://arxiv.org/html/2508.10925v1) |
| ❌ нет | Kimi, GLM без явного RU, coder-модели | — |
| ⛔ опровергнуто | llama-3.3-70b (офиц. 8 языков, RU нет) | [MODEL_CARD](https://github.com/meta-llama/llama-models/blob/main/models/llama3_3/MODEL_CARD.md) |

🛑 **GigaChat:** быстрый нативный русский, НО tool-вывод внутри `content` (нужен парсер
gigachat3) + слабая многошаговая оркестрация → **не мозг-оркестратор**, только быстрый ответ.
🛑 **Coder-модели:** «мультиязычность» = языки программирования, не естественные.

### Шаг 5. (Опц.) Роутер перед Ollama

⚠️ **tiny-dancer НЕ подходит как прокси.** `ruvnet/tiny-dancer` не существует
([404](https://github.com/ruvnet/tiny-dancer)); это подпакет монорепо
([ruvector](https://github.com/ruvnet/ruvector/tree/main/npm/packages/tiny-dancer),
npm `@ruvector/tiny-dancer`) — **библиотека FastGRNN** (`Router.route()` → кандидат +
`useLightweight`), **без HTTP-сервера, без `/v1`, без интеграции с Ollama**, pre-1.0. Не ставить перед Ollama.

Реалистично: фундамент **[LiteLLM Proxy](https://github.com/BerriAI/litellm)**
([routing](https://docs.litellm.ai/docs/routing),
[reliability](https://docs.litellm.ai/docs/proxy/reliability)); сверху —
**[Plano](https://github.com/katanemo/plano)** или
**[vLLM Semantic Router](https://github.com/vllm-project/semantic-router)**; drop-in —
**[NadirClaw](https://github.com/NadirRouter/NadirClaw)**. Обучаемые:
[RouteLLM](https://github.com/lm-sys/RouteLLM) (заброшен с 2024),
[aurelio-labs/semantic-router](https://github.com/aurelio-labs/semantic-router).

### Шаг 6. Прочитать точный id из /v1/models

```bash
curl -fsS "$CLOUDRU_BASE_URL/models" \
  -H "Authorization: Bearer $CLOUDRU_API_KEY" | jq -r '.data[].id'
```

Взять точный `CLOUD_MODEL_ID` из вывода. **Не подставлять id по памяти/из карточки HF** —
имя в Cloud.ru может отличаться.

### Шаг 7. Живой смоук-тест (обязателен)

Причина: независимых RU-бенчмарков по флагманам 2026 нет + у Cloud.ru свой парсер tool-call.
Проверить **на месте**:
1. русский диалог 3–5 промптов — нет сваливания в английский под нагрузкой инструментов;
2. tool-calling → структурный `tool_calls`, не текст в `content` (для Qwen на сервере — hermes-парсер);
3. многоходовый loop: вызов → результат обратно → продолжение, **без зацикливания**;
4. температура зафиксирована по карточке Instruct-2507.

---

## Стоп-условия

Остановиться / не делать:

1. **`CLOUD_MODEL_ID` не угадывать** — только из `curl $CLOUDRU_BASE_URL/models` (Шаг 6).
2. **`CLOUDRU_API_KEY` — только в `.env`.** Никогда в git, логи, чат, историю команд. Нет ключа — спросить человека, не хардкодить.
3. **Для русскоязычного пользователя не брать мозгом модель без подтверждённого русского.** Топовые tool-числа этого не компенсируют.
4. **NOT VERIFIED: русский у Qwen3.5-397B-A17B** — источник даёт только «201 language». Не выдавать за факт.
5. **Kimi K2.6 не ставить мозгом** — документированные циклы в tool-use (Шаг 1).
6. **Vendor-only числа 2026 без воспроизведения** — не считать за подтверждение.
7. **OpenClaw → Ollama строго БЕЗ `/v1`** (иначе ломается вызов инструментов).
8. **gpt-oss не формулирует русский финальный ответ** — русский не подтверждён; только оркестрация.
9. **GigaChat — не оркестратор:** tool в `content`, слабая многошаговость (Шаг 4).
10. **tiny-dancer как прокси перед Ollama — не использовать** (нет HTTP/`/v1`/Ollama; Шаг 5).
11. **Не пропускать смоук-тест** (Шаг 7) — карточка не гарантирует поведение парсера Cloud.ru.

> **NOT VERIFIED:** независимых русских бенчмарков ([MERA](https://mera.a-ai.ru/ru/text/leaderboard),
> ru_llm_arena) по **флагманам 2026** нет — только по предшественникам. Живой пробник обязателен.

---

## Критерий готовности

- [ ] `CLOUD_MODEL_ID` получен из `/v1/models` (не угадан), у модели подтверждённый русский
      **и** измеренный tool-calling (по умолчанию `Qwen/Qwen3-235B-A22B-Instruct-2507`)
- [ ] `CLOUDRU_API_KEY` только в `.env`; `git grep`/логи ключа не содержат
- [ ] Fallback настроен правильным для агента механизмом (Hermes `fallback_providers` /
      OpenClaw `model.fallbacks` / Ouroboros `OUROBOROS_MODEL_FALLBACKS`)
- [ ] OpenClaw-локаль — Ollama **без** `/v1`; Hermes/Ouroboros — **с** `/v1`
- [ ] Вспомогательные задачи направлены на `AUX_MODEL` (gpt-oss-20b)
- [ ] Смоук-тест пройден: русский под нагрузкой, структурный `tool_calls`, многоходовый loop
      без зацикливания, температура по карточке

Проверка отсутствия ключа в репозитории и логах:

```bash
git grep -nI -e "$CLOUDRU_API_KEY" 2>/dev/null && echo "FAIL: ключ в git" || echo "OK: ключа в git нет"
```

Источник назад: [00-ollama.md](00-ollama.md) (движок), [11-multi-agent-host.md](11-multi-agent-host.md)
(несколько агентов на одном хосте).
