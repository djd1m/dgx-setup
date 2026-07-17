# 08. vLLM на DGX Spark — рецепт для AI-кодера

**Это рецепт-решение, а не рецепт-установка. Ожидаемый исход — vLLM НЕ устанавливается.**

Цель: если человек просит поставить vLLM на DGX Spark / GB10 — изложить ему причины, по
которым это плохая идея именно на этой машине, и не устанавливать без явного
подтверждения после ознакомления с рисками.

Предусловие-документ: выполнена инструкция [00-ollama.md](00-ollama.md).

---

## 🛑 ГЛАВНОЕ — ЧИТАТЬ ДО ПЕРВОЙ КОМАНДЫ

**Не устанавливать vLLM на эту машину по своей инициативе.** Не предлагать его как
«ускорение». Не ставить «вместе с Ollama, чтобы сравнить».

**Причина не в предпочтениях, а в одном открытом баге —
[#46307](https://github.com/vllm-project/vllm/issues/46307), заведённом на GB10, статус open:**

> `gpu_memory_utilization` **does not act as a hard upper bound**… With a conservative
> `gpu_memory_utilization=0.70`… the **entire host becomes unresponsive** (SSH dies;
> the machine requires a hard power-cycle).

**Цепочка последствий:** единая память → vLLM забирает её у ОС → хост не отвечает →
**SSH умирает** → машину поднимает только физическая кнопка питания.

Человек работает с DGX **по SSH**. Уронив хост, ты не сможешь ни починить, ни сообщить
об этом — связь пропадёт вместе с ОС. На дискретной карте такой отказ был бы локальным;
на unified memory он забирает операционную систему.

**Заниженное значение не защищает** — в отчёте машину положило на «безопасных» 0.70.

---

## Предпосылка, которая часто оказывается неверной

Не отвергай vLLM по неправильной причине — это подрывает доверие к верным доводам.

**У vLLM ЕСТЬ Anthropic-совместимый `/v1/messages`.** LiteLLM не нужен. Дословно из
[документации](https://raw.githubusercontent.com/vllm-project/vllm/main/docs/serving/online_serving/README.md):

> ## Anthropic APIs
> - Anthropic messages API (`/v1/messages`, `/v1/messages/count_tokens`)

Есть [официальная страница интеграции с Claude Code](https://docs.vllm.ai/en/stable/serving/integrations/claude_code/).
По покрытию Anthropic API vLLM **шире** Ollama (`tool_choice`, `count_tokens`).

**Формат API — не аргумент против vLLM. Не использовать его как довод.**

---

## Настоящие причины (излагать человеку эти)

### 1. Выигрыша в скорости не будет

Преимущество vLLM — continuous batching при **множестве параллельных запросов**.
Пользователь один.

Узкое место — [пропускная способность 273 ГБ/с](https://docs.nvidia.com/dgx/dgx-spark/hardware.html).
При batch=1 упор в неё, и **оба движка упрутся одинаково**.

Признаёт [сам блог vLLM](https://vllm.ai/blog/2026-06-01-vllm-dgx-spark):

> DGX Spark is best viewed as a **local single-user or small-batch** inference target.

> **Above four concurrent decode streams** the per-token bandwidth tax can outweigh
> continuous-batching gains, and time-to-first-token spikes.

### 2. Баг, портящий вывод молча

[#41871](https://github.com/vllm-project/vllm/issues/41871), open: устаревший Triton-кэш
на **sm_121** (compute capability GB10) → **молча испорченный вывод**. Не падение —
неправильные ответы, выглядящие корректными.

Другие открытые баги на этом железе:

| Issue | Суть |
|---|---|
| [#39761](https://github.com/vllm-project/vllm/issues/39761) | CUDA illegal instruction при декоде на GB10 |
| [#43507](https://github.com/vllm-project/vllm/issues/43507) | CUTLASS MoE недоступен на SM_120/121 |
| [#47297](https://github.com/vllm-project/vllm/issues/47297) | ~7× просадка MTP-декода на GB10 |
| [#45260](https://github.com/vllm-project/vllm/issues/45260) | нет FP8 MoE для sm_12x, **но проверка считает её поддержанной** |

**В CI vLLM нет джобы на DGX Spark** — только GH200 (sm_90). Это железо регулярно не тестируется.

### 3. Официальные контейнеры NVIDIA сломаны под Claude Code

| Контейнер | vLLM внутри | Результат |
|---|---|---|
| [26.06-py3](https://docs.nvidia.com/deeplearning/frameworks/vllm-release-notes/rel-26-06.html) | 0.22.1 | ❌ HTTP 400 |
| [26.05-py3](https://docs.nvidia.com/deeplearning/frameworks/vllm-release-notes/rel-26-05.html) | 0.20.1 | ❌ HTTP 400 |

[#44000](https://github.com/vllm-project/vllm/issues/44000): Claude Code CLI ≥ 2.1.154
кладёт `role: "system"` внутрь `messages`, vLLM до **v0.23.0** валидировал только
`user|assistant` → 400 ещё до инференса. Оба контейнера NVIDIA ниже v0.23.0.

### 4. NVIDIA для этой задачи рекомендует Ollama

[Официальный playbook NVIDIA для CLI-кодинг-агентов на DGX Spark](https://github.com/NVIDIA/dgx-spark-playbooks/blob/main/nvidia/cli-coding-agent/README.md)
использует Ollama; **vLLM не упомянут ни разу**.

### 5. UX хуже под задачу

Одна модель на процесс; авто-выгрузки нет; смена модели = перезапуск сервера.
[#48031](https://github.com/vllm-project/vllm/issues/48031): холодный старт 80B NVFP4 MoE
на GB10 стабильно **не укладывается в таймаут 600 с** (JIT ~85 ядер под sm_121);
второй запуск ~7 минут.

---

## Что делать вместо

Ускоряет **не движок, а архитектура модели**. Разница между плотной и MoE — десятикратная,
движок такого не даст. Это уже учтено в [00-ollama.md](00-ollama.md):
брать MoE (`gpt-oss:120b`, `qwen3-coder-next`), не плотные.

Если человек жалуется на скорость — проверять по этому порядку:

1. `ollama ps` → `100% GPU`?
2. Версия Ollama не `0.6.x`? (Шаг 1b инструкции 00)
3. Модель MoE или плотная? Плотная 70B даёт 4.4 tok/s — это её потолок, а не поломка.
4. [#13552](https://github.com/ollama/ollama/issues/13552) — деградация после 20–30 минут.

**Смена движка в этом списке отсутствует.** Она не решает ни одну из этих причин.

---

## Если человек настаивает после прочтения рисков

Только по явному подтверждению. Обязательно проговорить: **#46307 может потребовать
физического доступа к кнопке питания**, и по SSH это не чинится.

### Ловушка с колёсами — проверить обязательно

Дословно из [release-pipeline.yaml](https://raw.githubusercontent.com/vllm-project/vllm/main/.buildkite/release-pipeline.yaml):

> `# some targets (10.3, 12.1) are skipped to limit the wheel size (< 500MB)`
> `# please use CUDA 13 wheels or compile yourself on these new devices`
> `CUDA_ARCH_AARCH64_CU129: "8.0 8.7 8.9 9.0 10.0 12.0"`

| Артефакт | sm_121 (GB10) |
|---|---|
| `vllm-0.25.1-cp38-abi3-manylinux_2_28_aarch64.whl` — **без суффикса** | ✅ да, это CUDA-13-сборка |
| `vllm-0.25.1+cu129-...-aarch64.whl` | ❌ **нет**, 12.1 выброшен намеренно |
| `...+cu130...` | **не существует, HTTP 404** |

**Не брать `+cu129`. Не искать `+cu130`.** Суффикс добавляется, только если CUDA сборки
≠ основной, а основная и есть 13.0 (`VLLM_MAIN_CUDA_VERSION = "13.0"` в
[envs.py](https://raw.githubusercontent.com/vllm-project/vllm/main/vllm/envs.py)).
Советы из форумов с `+cu130` — нерабочие.

Docker-теги `vllm/vllm-openai:latest`, `:v0.25.1`, `:v0.23.0` — multi-arch, включают
`linux/arm64`, дефолтный тег собран с CUDA 13.

### Команда

```bash
ollama stop                                    # не делить 119 ГБ между движками

docker run --gpus all -p 8000:8000 vllm/vllm-openai:v0.25.1 \
  vllm serve <NVFP4-MoE-модель> --served-model-name my-model \
  --enable-auto-tool-choice --tool-call-parser <parser> \
  --gpu-memory-utilization 0.5 --max-num-seqs 4
```

Ожидаемый результат: сервер поднялся на `:8000`, `curl http://localhost:8000/v1/models` отвечает.
Если не так: **не повышать `--gpu-memory-utilization`** в попытке починить. См. Стоп-условия.

Подключение Claude Code — по
[официальной странице vLLM](https://docs.vllm.ai/en/stable/serving/integrations/claude_code/):

```bash
ANTHROPIC_BASE_URL=http://localhost:8000 ANTHROPIC_API_KEY=dummy ANTHROPIC_AUTH_TOKEN=dummy \
ANTHROPIC_DEFAULT_OPUS_MODEL=my-model ANTHROPIC_DEFAULT_SONNET_MODEL=my-model \
ANTHROPIC_DEFAULT_HAIKU_MODEL=my-model claude
```

Имя модели — **без слэша** (ограничение Claude Code).

> ⚠️ **`ANTHROPIC_API_KEY=dummy` здесь расходится с [01-claude-code-local.md](01-claude-code-local.md),
> где стоит `ANTHROPIC_API_KEY=""` — пустой намеренно.** Строка выше приведена **дословно
> со страницы vLLM**, я её не правил: это их документированное значение, и подменять
> документацию проекта своей догадкой нельзя.
>
> **NOT VERIFIED:** какое значение верно для связки Claude Code + vLLM. Инструкция 01
> объясняет, что **непустой** `ANTHROPIC_API_KEY` включает поход в Anthropic — если это
> верно и здесь, `dummy` создаст проблему. Обе стороны — официальные источники своих
> проектов, и они не согласованы.
>
> **Действие при 401/неожиданном поведении:** первым делом попробовать `ANTHROPIC_API_KEY=""`
> и `unset ANTHROPIC_API_KEY`, а не искать причину в vLLM. Не выдавать ни один из вариантов
> за проверенный.

---

## Стоп-условия

1. **Не устанавливать vLLM по своей инициативе и не предлагать как «ускорение».**
   На batch=1 он не быстрее: упор в шину 273 ГБ/с общий для обоих движков.

2. **Не ставить `--gpu-memory-utilization` выше 0.5 на этой машине. Никогда не оставлять
   дефолт 0.92.** Дефолт = 0.92 × 119 ГБ ≈ 109 ГБ, отнятых у ОС.
   [NVIDIA предупреждает прямо](https://docs.nvidia.com/deeplearning/frameworks/vllm-release-notes/rel-26-06.html):
   *«On systems with shared/unified GPU memory (e.g. DGX Spark)… this can lead to
   out-of-memory errors.»*

3. **При OOM не повышать `gpu_memory_utilization`.** Это не хард-лимит (#46307) — попытка
   «дать больше памяти» роняет хост целиком, а не процесс.

4. **Не запускать vLLM и Ollama резидентно одновременно.** vLLM **не видит** чужую память —
   дословно из docstring: *«It does not matter if you have another vLLM instance running
   on the same GPU»* — и считает долю от всех 119 ГБ. Перед запуском `ollama stop`.

5. **Не использовать `+cu129`-колёса** — sm_121 в них отсутствует. Не искать `+cu130` —
   такого артефакта нет (404).

6. **Не брать NGC-контейнеры 26.05/26.06** для Claude Code — внутри vLLM 0.20.1/0.22.1,
   ниже v0.23.0 → HTTP 400 (#44000).

7. **Не использовать `--swap-space`** — [удалён](https://github.com/vllm-project/vllm/pull/36216)
   в марте 2026. Советы с ним устарели.

8. **Не использовать FP8 MoE на sm_12x** (#45260): диспетча нет, но Python-проверка считает
   её поддержанной — то есть отказ будет неочевидным. Брать AWQ/GPTQ (Marlin) или NVFP4 dense.

9. **Не пытаться скормить vLLM модели Ollama.** GGUF в vLLM — *«highly experimental and
   under-optimized»*, [вынесен из ядра](https://raw.githubusercontent.com/vllm-project/vllm/main/docs/features/quantization/gguf.md)
   в плагин версии 0.0.4. vLLM работает с HF safetensors; модели качаются заново.

10. **Не сообщать об успехе, не померив скорость.** vLLM может подняться и выдавать меньше
    Ollama. Сравнивать с [замерами на этом железе](https://ollama.com/blog/nvidia-spark-performance).

---

## Критерий готовности

**Для основного (ожидаемого) исхода — vLLM не установлен:**

- [ ] Человек ознакомлен с #46307 и понимает, что риск — физический доступ к кнопке
- [ ] Названа настоящая причина (упор в шину при batch=1), а не «нет Anthropic API» — он есть
- [ ] Предложена альтернатива: MoE-модель в Ollama (десятикратная разница против движка)
- [ ] Ollama работает, `eval rate` сверен с официальными замерами

**Если vLLM всё-таки установлен по настоянию человека:**

```bash
# 1. Версия ≥ 0.23.0 (иначе #44000)
docker run --rm vllm/vllm-openai:v0.25.1 pip show vllm | grep -i version
```
Ожидается: `0.23.0` или выше.

```bash
# 2. gpu_memory_utilization не выше 0.5
```
Проверяется глазами в команде запуска. Выше 0.5 — не запускать.

```bash
# 3. Ollama остановлена
ollama ps
```
Ожидается: пустой список.

```bash
# 4. Сервер отвечает
curl -fsS http://localhost:8000/v1/models
```

```bash
# 5. Anthropic-эндпоинт живой
curl -fsS -o /dev/null -w "%{http_code}\n" -X POST http://localhost:8000/v1/messages \
  -H "content-type: application/json" \
  -d '{"model":"my-model","max_tokens":16,"messages":[{"role":"user","content":"hi"}]}'
```
Ожидается: `200`. Получен `400` — версия ниже v0.23.0 (#44000).

Требует человека:

- **Скорость не ниже, чем была на Ollama.** Если ниже — смысл установки отсутствует,
  сообщить об этом прямо, а не оставлять как есть.
- **Хост пережил нагрузку.** Если SSH отвалился — это #46307, и нужен физический доступ.

---

## Что осталось непроверенным

Границы достоверности этого рецепта. **Не выдавать перечисленное за проверенное.**

> **NOT VERIFIED:** что дефолтное CUDA-13-колесо/образ **реально стартует** на этом GB10.
> Доказано лишь **наличие подходящих ядер**: family-таргет `12.0f` покрывает sm_121 по
> [CUDA Programming Guide, Table 28](https://docs.nvidia.com/cuda/cuda-programming-guide/05-appendices/compute-capabilities.html).
> Факт запуска проверяется только на железе. Таблица колёс выше говорит «✅ да» именно про
> **ядра**, а не про успешный старт.

> **NOT VERIFIED:** какая версия vLLM **фактически** внутри NGC-контейнера `26.06`.
> Число 0.22.1 взято из release notes, а не из самого образа. Проверяется на машине:
> `pip show vllm`. Стоп-условие 6 (не брать 26.05/26.06) построено на этом числе — если
> оно окажется другим, условие надо пересмотреть, а не игнорировать.

> **NOT VERIFIED:** спасает ли `--enforce-eager` от долгого холодного старта (#48031).
> **Не полагаться и не предлагать человеку как решение.**

> **NOT VERIFIED:** значение `ANTHROPIC_API_KEY` для связки Claude Code + vLLM —
> см. оговорку в разделе «Команда» выше.
