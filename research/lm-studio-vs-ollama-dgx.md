# LM Studio против Ollama на DGX Spark — верифицированный ресерч

**Дата:** 2026-07-24. **Метод:** рой из 6 независимых поисковых агентов (каждый обязан цитировать
первоисточник, который сам скачал) + 3 агента-верификатора, адверсариально перепроверивших
критичные утверждения, + прямые пробы URL с сервера (HTTP-коды, заголовки CDN). Ошибочные и
неточные утверждения роя перечислены в конце — они были поправлены верификаторами, в текст выше
попали уже исправленные версии.

**Вопрос:** можно ли использовать LM Studio для инференса локальных моделей на DGX Spark
(GB10, `aarch64`, DGX OS, 128 ГБ unified memory) — и как он соотносится с уже поднятой Ollama
([00-ollama.md](../for-ai/00-ollama.md)).

---

## TL;DR

1. **Да, LM Studio официально работает на DGX Spark** — Linux ARM64 поддерживается с 14 октября
   2025 ([официальный анонс](https://lmstudio.ai/blog/dgx-spark): «starting now, LM Studio ships
   for Linux on ARM (aarch64)»), со специальной сборкой llama.cpp-движка под CUDA 13.
   У NVIDIA есть [собственный плейбук LM Studio для Spark](https://github.com/NVIDIA/dgx-spark-playbooks/tree/main/nvidia/lm-studio).
2. **Для headless-сервера (наш случай) ставится не GUI-приложение, а `llmster`** — официальный
   демон без GUI: `curl -fsSL https://lmstudio.ai/install.sh | bash`, затем `lms daemon up`
   ([доки](https://lmstudio.ai/docs/developer/core/headless)). Требование «запустить GUI хотя бы
   раз» — история: оно касалось только старого пути через desktop-приложение.
3. **Критичное отличие для этого репозитория:** у Ollama есть
   [Anthropic-совместимый API](https://github.com/ollama/ollama/blob/main/docs/api/anthropic-compatibility.mdx)
   (`/v1/messages`) — Claude Code подключается напрямую. У LM Studio Anthropic-API **нет**
   (только [OpenAI-совместимый](https://lmstudio.ai/docs/developer/openai-compat) + свой REST) —
   для Claude Code понадобился бы переводчик типа LiteLLM. Для Hermes/Ouroboros (OpenAI-формат)
   оба равнозначны.
4. **Скорость:** оба — обёртки llama.cpp; опубликованных замеров именно LM-Studio-на-Spark нет
   ни у кого. Ollama на Spark по замерам [LMSYS](https://www.lmsys.org/blog/2025-10-13-nvidia-dgx-spark/)
   ощутимо медленнее голого llama.cpp (49.7 против ~59–83 tok/s decode на gpt-oss-20b).
5. **Лицензия:** Ollama — [MIT](https://github.com/ollama/ollama/blob/main/LICENSE); LM Studio —
   проприетарный, но [бесплатен и для работы с 08.07.2025](https://lmstudio.ai/blog/free-for-work);
   [условия](https://lmstudio.ai/terms) разрешают внутреннее использование и запрещают
   перепродавать его как сервис (SaaS). Для домашнего DGX — ок.

---

## 1. LM Studio на DGX Spark: статус поддержки

| Факт | Источник |
|---|---|
| Linux ARM64 (aarch64) поддерживается официально, анонс 14.10.2025 именно под DGX Spark | [lmstudio.ai/blog/dgx-spark](https://lmstudio.ai/blog/dgx-spark): «LM Studio ships for Linux on ARM (aarch64)» |
| Движок на Spark — вариант llama.cpp-движка LM Studio под **CUDA 13** | [там же](https://lmstudio.ai/blog/dgx-spark): «We brought up a new variant of LM Studio's llama.cpp engine with support for CUDA 13» |
| Linux ARM64 заявлен в системных требованиях; GUI-версия — AppImage, Ubuntu 20.04+ | [system-requirements](https://lmstudio.ai/docs/app/system-requirements): «supported on both x64 and ARM64 (aarch64) based systems» |
| NVIDIA ведёт официальный плейбук LM Studio для Spark, путь — headless `llmster` | [dgx-spark-playbooks/nvidia/lm-studio](https://github.com/NVIDIA/dgx-spark-playbooks/tree/main/nvidia/lm-studio): «curl -fsSL https://lmstudio.ai/install.sh \| bash», «lms server start --bind 0.0.0.0 --port 1234» |
| Текущая версия приложения — 0.4.20 (22.07.2026) | [changelog](https://lmstudio.ai/changelog) |
| На Linux работает только GGUF/llama.cpp; MLX — исключительно Apple Silicon | [docs/app](https://lmstudio.ai/docs/app): «On Apple Silicon Macs, LM Studio also supports … MLX» |

**Проверено прямыми пробами с сервера (2026-07-24):**

- `https://lmstudio.ai/install.sh` — существует, POSIX-скрипт, ставит демон **llmster v0.0.20-1**
  в `~/.lmstudio/bin`, случай `"Linux aarch64"` обрабатывается явно; требует `libatomic1`
  (Ubuntu: `sudo apt-get install -y libatomic1`); качает обычным curl/wget → **уважает `HTTPS_PROXY`**.
- Тарбол демона: `https://llmster.lmstudio.ai/download/0.0.20-1-linux-arm64.full.tar.gz` → HTTP 200.
- GUI AppImage: `https://installers.lmstudio.ai/linux/arm64/0.4.20-1/LM-Studio-0.4.20-1-arm64.AppImage`
  → HTTP 200, **1.34 ГБ**.
- ⚠️ Оба домена — за **Cloudflare** (`server: cloudflare` в заголовках). Для российских
  провайдеров это тот же режим, что у моделей Ollama ([00-ollama.md, Шаг 5](../for-ai/00-ollama.md)):
  скачивание, скорее всего, повиснет без `HTTPS_PROXY`. Модели LM Studio качает с huggingface.co —
  при проблемах есть только встроенный тумблер «Use LM Studio's Hugging Face Proxy»
  (с [0.3.9 Build 2](https://lmstudio.ai/blog/lmstudio-v0.3.9)); `HF_ENDPOINT`/зеркала для `lms`
  официально **не работают** — открытый запрос [lms#104](https://github.com/lmstudio-ai/lms/issues/104).

## 2. Headless-режим: llmster + lms

Терминология ([lmstudio-vs-llmster-vs-lms](https://lmstudio.ai/docs/app/basics/lmstudio-vs-llmster-vs-lms)):

- **LM Studio** — desktop-GUI (AppImage). На безголовом SSH-сервере не нужен.
- **llmster** — «LM Studio's headless daemon – a standalone background service that can run
  without a GUI»; desktop-приложение ставить не требуется вовсе.
- **lms** — CLI ([MIT, открыт](https://github.com/lmstudio-ai/lms)), управляет и тем и другим.

Жизненный цикл ([daemon-up](https://lmstudio.ai/docs/cli/daemon/daemon-up)): `lms daemon up/down/status/update`,
у `status` есть `--json`. Сервер: [`lms server start`](https://lmstudio.ai/docs/cli/server-start)
с `--bind 0.0.0.0` (по умолчанию `127.0.0.1`) и `--port N`. ⚠️ Порт по умолчанию — **не жёстко
1234, а «последний использованный»** («If not provided, uses the last used port») — в скриптах
задавать `--port` явно. Исторический баг «без GUI не работает» был реален
([bug-tracker#218](https://github.com/lmstudio-ai/lmstudio-bug-tracker/issues/218)) и закрыт
появлением llmster.

Модели: `lms get <модель>` (выбор кванта через `@`, напр. `qwen3-coder-30b@q4_k_m` —
[доки](https://lmstudio.ai/docs/cli/get)), `lms load <модель> --yes --ttl N --context-length N`,
`lms ls`/`lms ps` (есть `--json`), `lms unload --all`, `lms import <файл.gguf>`
([import](https://lmstudio.ai/docs/app/advanced/import-model)). Хранилище —
`~/.lmstudio/models/<издатель>/<модель>/…gguf` (структура Hugging Face).
Флаг `--yes` существует (используется в официальном systemd-юните), короткое `-y` в доках не
подтверждено — в скриптах писать `--yes`.

Резидентность ([ttl-and-auto-evict](https://lmstudio.ai/docs/developer/core/ttl-and-auto-evict)):
JIT-загрузка по первому API-запросу включена по умолчанию, простой 60 минут → выгрузка; Auto-Evict
держит максимум 1 JIT-модель. Модели, загруженные явно через `lms load`, **живут без TTL, пока не
выгрузишь** — то, что нужно серверу.

**Автозапуск при перезагрузке — официальный systemd-юнит**
([headless_llmster](https://lmstudio.ai/docs/developer/core/headless_llmster)), проверен дословно:

```ini
# /etc/systemd/system/lmstudio.service (YOUR_USERNAME заменить)
[Unit]
Description=LM Studio Server

[Service]
Type=oneshot
RemainAfterExit=yes
User=YOUR_USERNAME
Environment="HOME=/home/YOUR_USERNAME"
ExecStartPre=/home/YOUR_USERNAME/.lmstudio/bin/lms daemon up
ExecStartPre=/home/YOUR_USERNAME/.lmstudio/bin/lms load openai/gpt-oss-20b --yes
ExecStart=/home/YOUR_USERNAME/.lmstudio/bin/lms server start
ExecStop=/home/YOUR_USERNAME/.lmstudio/bin/lms daemon down

[Install]
WantedBy=multi-user.target
```

(строка `lms load` — опциональна: можно положиться на JIT; пути абсолютные — systemd не понимает `~`).

## 3. API для агентов

| Возможность | LM Studio | Ollama |
|---|---|---|
| OpenAI-совместимый | ✅ `/v1/chat/completions`, `/v1/completions`, `/v1/models`, `/v1/embeddings`, [`/v1/responses`](https://lmstudio.ai/docs/app/api/endpoints/openai) (порт 1234) | ✅ то же + `/v1/responses` (порт 11434), [не поддержаны](https://docs.ollama.com/api/openai-compatibility): `logprobs`, `tool_choice`, `logit_bias`, `n` |
| **Anthropic-совместимый** (`/v1/messages` — для Claude Code) | ❌ нет | ✅ [есть](https://github.com/ollama/ollama/blob/main/docs/api/anthropic-compatibility.mdx) |
| Свой REST | [`/api/v1/…`](https://lmstudio.ai/docs/developer/rest/endpoints) (v0 объявлен устаревшим), стейтфул-чат [`POST /api/v1/chat`](https://lmstudio.ai/docs/developer/rest/chat) с `response_id`/`previous_response_id` | `/api/generate`, `/api/chat`, `/api/tags`, … |
| Tool calling | ✅ [формат OpenAI, включая стриминг](https://lmstudio.ai/docs/developer/openai-compat/tools); качество зависит от модели | ✅ но с [известными багами `/v1`-слоя](../for-ai/00-ollama.md) (пустой ответ после `role:"tool"` — issues #14181/#9802 …) |
| Structured output | ✅ [`response_format: json_schema`](https://lmstudio.ai/docs/developer/openai-compat/structured-output), грамматики llama.cpp | ✅ [`format: <json schema>`](https://ollama.com/blog/structured-outputs) |
| Параллельные запросы | ✅ с [0.4.0 (28.01.2026)](https://lmstudio.ai/blog/0.4.0) continuous batching, [«Max Concurrent Predictions», по умолчанию 4](https://lmstudio.ai/docs/app/advanced/parallel-requests) (нужен llama.cpp-движок ≥ 2.0.0) | ✅ `OLLAMA_NUM_PARALLEL` (по умолч. 1); на GB10 параллельность роняла qwen3.5 ([#14621](https://github.com/ollama/ollama/issues/14621)) |
| Несколько моделей сразу | ✅ JIT + TTL | ✅ `OLLAMA_MAX_LOADED_MODELS` (по умолч. 3), очередь `OLLAMA_MAX_QUEUE` (512) |

## 4. Тонкие настройки производительности

LM Studio даёт **на модель** (через GUI/[конфиг загрузки](https://lmstudio.ai/docs/typescript/api-reference/llm-load-model-config)):
Flash Attention, квантизация K- и V-кэша по отдельности, длина контекста, число экспертов MoE,
[спекулятивное декодирование с draft-моделью](https://lmstudio.ai/docs/app/advanced/speculative-decoding)
(в доках описано только через GUI в режиме Power User). Ollama — только **грубые серверные**
переменные: `OLLAMA_FLASH_ATTENTION`, `OLLAMA_KV_CACHE_TYPE`, `OLLAMA_CONTEXT_LENGTH`
([FAQ](https://docs.ollama.com/faq)); спекулятивное декодирование появилось лишь в мае 2026 и
только для семейства gemma4 ([PR #15980](https://github.com/ollama/ollama/pull/15980)).

## 5. Бенчмарки на DGX Spark (все цифры — с первоисточниками)

Структурная особенность GB10: prefill упирается в вычисления (Blackwell силён), генерация —
в шину памяти 273 ГБ/с. Плотная 32B читает ~18 ГБ на токен → теоретический потолок ~15 tok/s,
фактически ~10.7 ([замер DandinPower](https://github.com/DandinPower/llama.cpp_bench/blob/main/dgx_spark/report.md):
«confirming the system is hard-bound by LPDDR5x memory bandwidth»). Та же 30B, но MoE — **~89 tok/s**:
разница 8×, поэтому на Spark правят MoE (совпадает с выводом [00-ollama.md](../for-ai/00-ollama.md)).

| Замер | Модель | Prefill, tok/s | Генерация, tok/s | Источник |
|---|---|---|---|---|
| llama.cpp (канонический тред Гергановва) | gpt-oss-20b MXFP4 | ~3600 | ~59 (позже до ~61) | [ggml-org/llama.cpp#16578](https://github.com/ggml-org/llama.cpp/discussions/16578) |
| llama.cpp | gpt-oss-120b MXFP4 | ~1723→1956 | 38.5→~60 (рост от оптимизаций) | [там же](https://github.com/ggml-org/llama.cpp/discussions/16578) |
| NVIDIA (оф. блог) | gpt-oss-20b llama.cpp | 3670 | 82.7 | [developer.nvidia.com](https://developer.nvidia.com/blog/how-nvidia-dgx-sparks-performance-enables-intensive-ai-tasks) |
| **Ollama** (LMSYS) | gpt-oss-20b | 2053 | **49.7** | [lmsys.org](https://www.lmsys.org/blog/2025-10-13-nvidia-dgx-spark/) |
| **Ollama** (оф. блог Ollama) | gpt-oss-120b | — | 41.1 | [ollama.com/blog](https://ollama.com/blog/nvidia-spark-performance) |
| SGLang оптимизированный | gpt-oss-120b | — | ~50 | [lmsys.org (нояб.)](https://www.lmsys.org/blog/2025-11-03-gpt-oss-on-nvidia-dgx-spark/) |

Выводы: (а) Ollama на Spark **медленнее голого llama.cpp** на той же модели; (б) docker-образ
Ollama на Spark имел серьёзный баг производительности — ставить нативно
([форум NVIDIA](https://forums.developer.nvidia.com/t/very-poor-performance-with-ollama-on-dgx-spark-looking-for-help/353456));
(в) **опубликованных чисел LM-Studio-на-Spark не существует** ни в одном авторитетном источнике —
его движок llama.cpp, поэтому ожидается паритет с upstream минус лаг версии, но это вывод, а не
замер ([Simon Willison](https://simonwillison.net/2025/Oct/14/nvidia-dgx-spark/) сборку для Spark
упоминает, но не мерил). Обещать цифры нельзя — только мерить на месте.

## 6. Лицензия и приватность

- Ollama: [MIT](https://github.com/ollama/ollama/blob/main/LICENSE), полностью открыта.
- LM Studio: приложение и llmster **проприетарны**; открыты (MIT) [lms](https://github.com/lmstudio-ai/lms),
  SDK-и и mlx-engine. [Бесплатен для дома и работы с 08.07.2025](https://lmstudio.ai/blog/free-for-work)
  («Starting today, LM Studio is free to use both at home and at work»). [Условия](https://lmstudio.ai/terms):
  «solely for Your personal and / or internal business purposes», запрещены SaaS/перепродажа и
  реверс-инжиниринг. Домашний сервер для своих агентов — разрешённый случай.
- Приватность: [официально](https://lmstudio.ai/app-privacy) — локальные диалоги никуда не
  уходят, сеть нужна для поиска/скачивания моделей (huggingface.co) и проверки обновлений;
  [работает полностью офлайн](https://www.lmstudio.ai/docs/app/offline).

## 7. Ollama на Spark — что нового с [00-ollama.md](../for-ai/00-ollama.md) (2026-07-24)

- GB10 в [официальной матрице GPU](https://raw.githubusercontent.com/ollama/ollama/main/docs/gpu.mdx)
  (compute capability 12.1); [плейбук NVIDIA](https://github.com/NVIDIA/dgx-spark-playbooks/tree/main/nvidia/ollama)
  ставит обычным `install.sh`, доступ через SSH-туннель на 11434.
- Текущий релиз **v0.32.3 (23.07.2026)**: «lower memory use on Linux CUDA/ROCm iGPUs» —
  GB10-фиксы в релиз-нотах всегда называются «NVIDIA iGPU»/«shared-memory GPU», слова
  «Spark»/«GB10» там не встречаются.
- ⚠️ Открытый issue [#16610](https://github.com/ollama/ollama/issues/16610): на GB10 после
  0.30.x большая модель выгружается/перезагружается между запросами вопреки `OLLAMA_KEEP_ALIVE`
  (57 сек на каждый запрос против 0.4 сек на 0.24.0). Нюанс от мейнтейнера (dhiltgen): репортер
  чередовал **два разных тега одной модели** (разные GGUF-хэши) — планировщик считает их разными
  моделями и по preflight-прогнозу памяти выгружает одну ради другой; «регрессией» это называет
  автор, не мейнтейнер. Фикса нет (открыт и после v0.32.3). Практический вывод: **работать с одним
  тегом модели**, не плодить варианты, и следить за `OLLAMA_NUM_PARALLEL`/контекстом.
- Vision-модели: до 0.31.2 проекторы не оффлоадились на GPU на shared-memory
  ([#16419](https://github.com/ollama/ollama/issues/16419), поправлено в
  [v0.31.2](https://github.com/ollama/ollama/releases)).

## 8. Что рой наврал, а верификация поправила (сохранить как урок)

1. «Stateful-эндпоинт `/v1/chat`» → на самом деле [`POST /api/v1/chat`](https://lmstudio.ai/docs/developer/rest/chat);
   `/v1/responses` — отдельный OpenAI-совместимый эндпоинт, не путать.
2. «Порт по умолчанию 1234» → в [доках `lms server start`](https://lmstudio.ai/docs/cli/server-start)
   порт по умолчанию — «последний использованный»; 1234 — лишь начальный.
3. «HF-прокси с 0.3.9» → точнее с **0.3.9 Build 2**; `HF_ENDPOINT` официально не поддержан
   ([lms#104](https://github.com/lmstudio-ai/lms/issues/104) без ответа мейнтейнеров).
4. «`lms load -y`» → в доках только `--yes` (в официальном systemd-юните); `-y` нигде не подтверждён.
5. Один агент выдал pp gpt-oss-20b = 2008 tok/s из #16578 — расходится с 3600–3670 в трёх
   других источниках; помечено как вероятная ошибка извлечения таблицы, в выводы не пошло.

---

**Продукты этого ресерча:** [for-human/15-lm-studio.md](../for-human/15-lm-studio.md),
[for-ai/15-lm-studio.md](../for-ai/15-lm-studio.md), [scripts/install-lm-studio.sh](../scripts/install-lm-studio.sh).
