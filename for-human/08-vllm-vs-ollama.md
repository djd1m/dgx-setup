# 08. vLLM вместо Ollama? Разбор для DGX Spark

Вопрос законный: vLLM — движок инференса, который считается быстрее Ollama. Стоит ли
поставить его вместо или вместе?

**Короткий ответ для DGX Spark: остаться на Ollama. vLLM сейчас не ставить — ни вместо,
ни вместе.** Ниже — почему, с цифрами и ссылками, чтобы ты мог не верить на слово.

---

## Сначала — то, что обычно называют главным, и оно оказалось неважным

Первое, что проверяют при выборе движка под Claude Code, — **формат API**. Claude Code
понимает только Anthropic Messages, а большинство движков говорят по-OpenAI'вски, и тогда
нужна прослойка-переводчик (как в [02-claude-code-cloudru.md](02-claude-code-cloudru.md)).

**У vLLM с этим всё в порядке.** Дословно из
[документации vLLM](https://raw.githubusercontent.com/vllm-project/vllm/main/docs/serving/online_serving/README.md):

> ## Anthropic APIs
> - Anthropic messages API (`/v1/messages`, `/v1/messages/count_tokens`)

Есть даже [официальная страница интеграции с Claude Code](https://docs.vllm.ai/en/stable/serving/integrations/claude_code/).
LiteLLM не нужен.

По покрытию Anthropic API vLLM **шире** Ollama: поддерживает `tool_choice` и
`count_tokens`, которых у Ollama [явно нет](https://raw.githubusercontent.com/ollama/ollama/main/docs/api/anthropic-compatibility.mdx)
(раздел «Not supported»).

**То есть здесь ничья, и решают другие вещи.**

---

## Причина 1: на этой машине vLLM не станет быстрее

Главное преимущество vLLM — **continuous batching** и PagedAttention: эффективная
обработка **множества одновременных запросов**. У тебя один пользователь.

А узкое место DGX Spark — [пропускная способность памяти, 273 ГБ/с](https://docs.nvidia.com/dgx/dgx-spark/hardware.html).
При генерации по одному запросу упор именно в неё, и **движок тут ни при чём: оба упрутся
в одну и ту же шину**.

Это не домысел — так пишет **сам блог vLLM** про эту машину
([vLLM on DGX Spark](https://vllm.ai/blog/2026-06-01-vllm-dgx-spark)):

> DGX Spark is best viewed as a **local single-user or small-batch** inference target
> for large NVFP4 models.

> **Above four concurrent decode streams** the per-token bandwidth tax can outweigh
> continuous-batching gains, and time-to-first-token spikes.

Авторы движка прямо говорят: на этом железе батчинг перестаёт помогать уже после четырёх
потоков. Ради чего тогда сложность?

**Ускоряет не движок, а архитектура модели.** Разница между плотной 60 ГБ (~4.5 tok/s) и
MoE (~45 tok/s) — в десять раз. Никакой движок такого не даст. Это уже учтено в
[00-ollama.md](00-ollama.md).

---

## Причина 2: 🛑 открытый баг вешает машину целиком

Это решающий довод, и он про твою ситуацию конкретно.

vLLM резервирует память заранее — параметр `gpu_memory_utilization`, по умолчанию **0.92**.
На обычной видеокарте это доля видеопамяти. **На DGX Spark память единая** — то есть
0.92 × 119 ГБ ≈ **109 ГБ отбирается из того же пула, где живёт операционная система**.

NVIDIA предупреждает об этом прямо
([Known Issues, контейнер 26.06](https://docs.nvidia.com/deeplearning/frameworks/vllm-release-notes/rel-26-06.html)):

> vLLM serve uses aggressive GPU memory allocation by default… On systems with
> shared/unified GPU memory (e.g. **DGX Spark** or Jetson platforms), this can lead to
> out-of-memory errors.

Но хуже другое. Открытый баг [#46307](https://github.com/vllm-project/vllm/issues/46307),
заведён **на GB10**, статус open:

> `gpu_memory_utilization` **does not act as a hard upper bound**… With a conservative
> `gpu_memory_utilization=0.70`… the **entire host becomes unresponsive** (SSH dies;
> the machine requires a hard power-cycle).

> A parameter value that should be conservative (0.70) can render the entire machine unusable.

**Ты работаешь с DGX по SSH.** На дискретной карте такое падало бы чисто — умер процесс,
машина жива. На единой памяти умирает операционная система, и восстановить это удалённо
**нельзя**: нужен физический доступ к кнопке питания.

Причём заниженное значение не спасает — в отчёте машину положило именно на «безопасных» 0.70.

---

## Причина 3: баг, который портит ответы молча

[#41871](https://github.com/vllm-project/vllm/issues/41871), тоже open: устаревший
Triton-кэш на sm_121 (это compute capability GB10) даёт **молча испорченный вывод**.

Не падение. Не ошибку. Просто неправильные ответы, выглядящие нормальными.

Из всех режимов отказа этот — худший: ты не узнаешь, что что-то не так, и будешь
принимать решения по битым данным.

Другие открытые баги ровно на этом железе:

| Issue | Суть |
|---|---|
| [#39761](https://github.com/vllm-project/vllm/issues/39761) | CUDA illegal instruction при декоде на GB10 |
| [#43507](https://github.com/vllm-project/vllm/issues/43507) | CUTLASS MoE недоступен на SM_120/121 |
| [#47297](https://github.com/vllm-project/vllm/issues/47297) | ~7× просадка MTP-декода на GB10 |
| [#45260](https://github.com/vllm-project/vllm/issues/45260) | нет FP8 MoE для sm_12x — **при этом проверка считает её поддержанной** |

И объясняющая деталь: **в CI vLLM нет джобы на DGX Spark** — только GH200. Твоё железо
регулярно не тестируется. Отсюда и список.

---

## Причина 4: официальные контейнеры NVIDIA сломаны под Claude Code

Казалось бы, безопасный путь — взять готовый контейнер от NVIDIA,
[`nvcr.io/nvidia/vllm`](https://catalog.ngc.nvidia.com/orgs/nvidia/containers/vllm).
Не выйдет:

| Контейнер | vLLM внутри | Claude Code |
|---|---|---|
| [26.06-py3](https://docs.nvidia.com/deeplearning/frameworks/vllm-release-notes/rel-26-06.html) | 0.22.1 | ❌ HTTP 400 |
| [26.05-py3](https://docs.nvidia.com/deeplearning/frameworks/vllm-release-notes/rel-26-05.html) | 0.20.1 | ❌ HTTP 400 |

Причина — issue [#44000](https://github.com/vllm-project/vllm/issues/44000): Claude Code
CLI начиная с 2.1.154 кладёт `role: "system"` внутрь массива `messages`, а vLLM до
**v0.23.0** валидировал только `user|assistant` и отвечал 400 ещё до инференса.

Оба контейнера NVIDIA ниже v0.23.0. То есть официальный путь ведёт в стену, а рабочий —
это апстрим-образ, который NVIDIA на Spark не тестирует.

---

## Причина 5: NVIDIA сама рекомендует Ollama

Самый показательный аргумент.

[Официальный playbook NVIDIA для CLI-кодинг-агентов на DGX Spark](https://github.com/NVIDIA/dgx-spark-playbooks/blob/main/nvidia/cli-coding-agent/README.md)
построен на **Ollama**:

```bash
ollama launch claude --model qwen3.6
```

**vLLM в нём не упомянут ни разу.** Производитель железа, продающий vLLM в собственном
контейнере, для этой задачи на этой машине выбрал Ollama.

---

## Причина 6: под твою задачу у vLLM хуже UX

| | Ollama | vLLM |
|---|---|---|
| Моделей на процесс | много, грузятся по требованию | **одна** |
| Авто-выгрузка | да, `OLLAMA_KEEP_ALIVE` | **нет** |
| Смена модели | `ollama run другая-модель` | перезапуск сервера |
| Холодный старт | секунды | **до ~10 минут** на GB10 |

Про старт — не преувеличение: [#48031](https://github.com/vllm-project/vllm/issues/48031),
на GB10 холодный старт 80B NVFP4 MoE стабильно **не укладывается в таймаут 600 секунд**
из-за JIT-компиляции ~85 CUDA-ядер под sm_121. Второй запуск — около 7 минут.

Ollama-подобного «переключился на другую модель» у vLLM нет.
[Sleep mode](https://raw.githubusercontent.com/vllm-project/vllm/main/docs/features/sleep_mode.md) —
не замена: ни таймаута, ни авто-выгрузки, только руками, и дока предупреждает, что эти
эндпоинты *«should not be exposed to users»*.

---

## Про «поставить оба сразу»

Порты не конфликтуют: Ollama — 11434, vLLM — 8000.

**Конфликтует память.** Дословно из docstring `gpu_memory_utilization`:

> This is a **per-instance limit**, and only applies to the current vLLM instance. It
> **does not matter if you have another vLLM instance** running on the same GPU.

vLLM **не видит** чужую память и считает свою долю от всех 119 ГБ. Ollama при этом держит
модель резидентной пять минут после запроса. Два резидентных движка на единой памяти — это
гонка за один пул, а с учётом #46307 — риск положить хост.

**Держать оба демона одновременно на этой машине смысла нет.**

---

## GGUF: модели Ollama в vLLM не переиспользуются

Мысль «скачал модели для Ollama, отдам их vLLM» не сработает. Дословно из
[документации vLLM](https://raw.githubusercontent.com/vllm-project/vllm/main/docs/features/quantization/gguf.md):

> GGUF support in vLLM is **highly experimental and under-optimized** at the moment, it
> might be incompatible with other features.

> GGUF support has migrated to OOT [vllm-gguf-plugin](https://github.com/vllm-project/vllm-gguf-plugin).

То есть поддержку GGUF вынесли из ядра в отдельный плагин (версия на PyPI — **0.0.4**).
Причина в [RFC #39583](https://github.com/vllm-project/vllm/issues/39583): доля GGUF ≈ 0.1%,
и пользователи говорят, что *«running GGUF models with llamacpp to be faster»* именно на
`bs=1` — то есть на твоём сценарии.

vLLM работает с HF safetensors. Модели придётся качать заново, в другом формате.

---

## Если всё-таки хочется попробовать

Не на рабочей машине в разгар дела, и помня про #46307 (нужен физический доступ к кнопке).

```bash
# ТОЛЬКО дефолтный тег (без суффикса) = CUDA 13 = поддерживает sm_121.
# НИКОГДА не cu129 — там 12.1 выброшен намеренно.
docker run --gpus all -p 8000:8000 vllm/vllm-openai:v0.25.1 \
  vllm serve <NVFP4-MoE-модель> --served-model-name my-model \
  --enable-auto-tool-choice --tool-call-parser <parser> \
  --gpu-memory-utilization 0.5 --max-num-seqs 4
```

**Ловушка с колёсами — на ней спотыкаются все.** Дословно из
[release-pipeline.yaml](https://raw.githubusercontent.com/vllm-project/vllm/main/.buildkite/release-pipeline.yaml):

> `# some targets (10.3, 12.1) are skipped to limit the wheel size (< 500MB)`
> `# please use CUDA 13 wheels or compile yourself on these new devices`
> `CUDA_ARCH_AARCH64_CU129: "8.0 8.7 8.9 9.0 10.0 12.0"`

| Артефакт | Работает на GB10? |
|---|---|
| `vllm-0.25.1-...-aarch64.whl` (без суффикса) | ✅ да — это CUDA-13-сборка |
| `vllm-0.25.1+cu129-...-aarch64.whl` | ❌ нет — 12.1 выброшен |
| `...+cu130...` | не существует, **HTTP 404** |

Советы из форумов с `+cu130` — нерабочие. Суффикс добавляется, только если CUDA сборки
отличается от основной, а основная и есть 13.0.

Обязательные условия:

- **Версия ≥ v0.23.0**, иначе баг #44000 (HTTP 400 с Claude Code). Лучше v0.25.1 — там же
  фикс единой памяти через `psutil`.
- **`--gpu-memory-utilization` начинать с 0.5**, не с дефолтных 0.92. И помнить: это
  **не твёрдая граница** (#46307).
- Имя модели **без слэша** — ограничение Claude Code.
- Сначала `ollama stop`, чтобы не делить 119 ГБ.
- **Обходить FP8 MoE** (#45260): проверка считает её поддержанной, а диспетча для sm_12x нет.
  Безопаснее AWQ/GPTQ через Marlin или NVFP4 dense.

Ещё: `--swap-space` больше не существует —
[удалён](https://github.com/vllm-project/vllm/pull/36216) в марте 2026. Советы с ним устарели.

---

## Что осталось непроверенным

> **NOT VERIFIED:**
> - Что дефолтное CUDA-13-колесо **реально стартует** на GB10. Доказано, что нужные ядра
>   в нём есть (family-таргет `12.0f` покрывает sm_121 —
>   [CUDA Programming Guide, Table 28](https://docs.nvidia.com/cuda/cuda-programming-guide/05-appendices/compute-capabilities.html)),
>   но факт запуска проверяется только на железе.
> - Какая версия vLLM фактически внутри NGC-контейнера `26.06` — по release notes 0.22.1,
>   на машине проверяется через `pip show vllm`.
> - Спасает ли `--enforce-eager` от долгого холодного старта.

---

## Итог

| Критерий | Ollama | vLLM |
|---|---|---|
| Anthropic `/v1/messages` | ✅ | ✅ (шире: `tool_choice`, `count_tokens`) |
| Выигрыш в скорости при 1 пользователе | — | **нет, упор в шину** |
| Риск положить хост | нет | **да, #46307, нужен hard power-cycle** |
| Молча портит вывод | нет | **да, #41871 на sm_121** |
| Официальные контейнеры NVIDIA | — | **сломаны под Claude Code** |
| Тестируется на GB10 | ✅ [партнёрство с NVIDIA](https://ollama.com/blog/nvidia-spark) | ❌ нет джобы в CI |
| Что рекомендует NVIDIA | ✅ [playbook](https://github.com/NVIDIA/dgx-spark-playbooks/blob/main/nvidia/cli-coding-agent/README.md) | не упомянут |
| Смена моделей | по требованию | перезапуск, старт до 10 мин |

**vLLM — хороший движок. Просто не для одного пользователя на машине с медленной шиной
и единой памятью.** Его сильные стороны — там, где много параллельных запросов и
дискретные карты с быстрой памятью. Здесь их нет, а слабые стороны есть.

Вернуться к вопросу имеет смысл, если появится **много одновременных пользователей** — тогда
батчинг начнёт окупаться. Для этого сначала должен закрыться #46307.
