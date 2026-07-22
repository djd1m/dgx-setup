# 00. Ollama — рецепт для AI-кодера

Цель: поднять Ollama как systemd-службу на DGX Spark / GB10 (`aarch64`, DGX OS) и скачать модели, подходящие этому железу.

Официальные источники: [ollama.com/download/linux](https://ollama.com/download/linux),
[github.com/ollama/ollama](https://github.com/ollama/ollama),
[матрица поддержки GPU](https://docs.ollama.com/gpu).
Актуальная версия на момент написания — **v0.32.0** (11 июля 2026).

---

## Предусловия

Выполнить ДО установки. Требования к GPU: [docs.ollama.com/gpu](https://docs.ollama.com/gpu).

### Шаг П1. Определить архитектуру — от этого зависит всё дальнейшее

```bash
uname -m
```

| Результат | Что это | Действие |
|---|---|---|
| `aarch64` | DGX Spark / GB10 (в т.ч. Dell Pro Max with GB10, HP, Lenovo, ASUS) | продолжать, бинарник — `arm64` |
| `x86_64` | классический DGX с картами A100/H100 | продолжать, бинарник — `amd64`, **Матрицу моделей читать критически** |
| другое | неизвестная платформа | **STOP** — спросить человека |

Не подставлять архитектуру по памяти или по слову «DGX» в названии машины. **Только по `uname -m`.**
[DGX Spark](https://docs.nvidia.com/dgx/dgx-spark/hardware.html) несёт 20-ядерный Arm-процессор
(Grace) — это `aarch64`, несмотря на то, что «DGX» ассоциируется с x86.

Опознать машину точнее:

```bash
cat /sys/class/dmi/id/product_name /sys/class/dmi/id/sys_vendor
```

Ожидаемый результат на OEM-версии: например, `Dell Pro Max with GB10 FCM1253` / `Dell Inc.`
Если не так: не страшно, решает `uname -m`. Строка нужна для Шага 2 инструкции
[03-nemoclaw](03-nemoclaw.md) — записать её дословно, обе части.

> **NOT VERIFIED:** что «Dell Pro Max with GB10» — **официально** OEM-версия DGX Spark.
> Dell слово «DGX Spark» на своих страницах **не употребляет**, называет продукт
> «AI Accelerator». Вывод построен на совпадении спецификаций и на том, что NVIDIA
> [называет Dell партнёром по производству DGX Spark](https://nvidianews.nvidia.com/news/nvidia-announces-dgx-spark-and-dgx-station-personal-ai-computers).
> Практически всё, написанное для DGX Spark, применимо. **Но человеку не утверждать
> «у тебя DGX Spark» как факт** — говорить «машина класса DGX Spark под брендом Dell».

### Шаг П2. Драйвер и GPU

```bash
nvidia-smi
```

| Проверка | Ожидаемый результат | Если не так |
|---|---|---|
| `nvidia-smi` отработал | вывод с таблицей GPU | **STOP** — GPU не видны, разбираться до установки |
| `Driver Version:` | **550 или новее** | **STOP** — обновить драйвер. Со старее 550 Ollama не увидит GPU и молча уйдёт на процессор: работает, но в десятки раз медленнее |
| Compute capability | **5.0 или выше** | **STOP** — GPU не годится |
| Строка `NVIDIA GB10` в таблице | подтверждает DGX Spark | — |

Compute capability GB10 — **12.1**. GPU перечислен в
[официальной матрице Ollama](https://docs.ollama.com/gpu) строкой `12.1 | NVIDIA | GB10 (DGX Spark)`,
поддержка заявленная, не случайная.

### 🛑 Шаг П3. `Memory-Usage: Not Supported` — НЕ считать ошибкой

На GB10 `nvidia-smi` покажет в колонке памяти `Not Supported`.
**Это штатное поведение. Не чинить, не искать причину, не откатывать драйвер.**

Дословно из [Known Issues DGX Spark](https://docs.nvidia.com/dgx/dgx-spark/known-issues.html):

> On iGPU platforms, nvidia-smi will display "Memory-Usage: Not Supported" even though
> per-process GPU memory is listed. **This is expected** because iGPUs do not have
> dedicated framebuffer memory.

Причина: память **единая (unified)** для CPU и GPU, выделенного фреймбуфера нет.
**Отсюда следует: переменной «VRAM одной карты» на этой машине не существует.**
Память читать так:

```bash
free -g
```

Ожидаемый результат: около **119** в колонке «всего» (128 ГБ минус
[2 ГБ carveout дисплея](https://docs.nvidia.com/dgx/dgx-spark/dgx-spark.pdf) минус ОС).
Если не так: записать фактическую цифру и продолжать.

> **NOT VERIFIED:** сколько именно памяти доступно **GPU под модель**. NVIDIA такого числа
> не публикует — при единой памяти распределение динамическое. **Не вычислять и не обещать
> человеку конкретную цифру.**
>
> 🛑 **И отдельно: `cudaMemGetInfo` ЗАНИЖАЕТ доступную память** — официальная оговорка из
> [Known Issues](https://docs.nvidia.com/dgx/dgx-spark/known-issues.html): он не учитывает
> страницы, вытесненные в SWAP. Если инструмент или библиотека сообщает «мало памяти»,
> опираясь на `cudaMemGetInfo`, — **это не повод верить**. Сверяться с `free -g`.
> Воркэраунд для сброса кэша (только по решению человека):
> ```bash
> sudo sh -c 'sync; echo 3 > /proc/sys/vm/drop_caches'
> ```

---

## Переменные

Получить/решить до старта.

| Переменная | Как получить | Пример / формат |
|---|---|---|
| `ARCH` | `uname -m` | `aarch64` (DGX Spark) или `x86_64` |
| `OLLAMA_BINARY` | по `ARCH` | `aarch64` → `ollama-linux-arm64.tar.zst`; `x86_64` → `ollama-linux-amd64.tar.zst` |
| `MEM_TOTAL_GB` | `free -g`, колонка «всего» | `119` на DGX Spark. **Единая память CPU+GPU, не VRAM** |
| `DRIVER_VERSION` | `nvidia-smi`, верхняя строка `Driver Version:` | должно быть ≥ 550 |
| `PROXY_URL` | взять у человека; нужен только если `ollama pull` виснет на 0% (Шаг 5) | `https://адрес-твоего-прокси` |

**На DGX Spark переменных `VRAM_PER_GPU`, `GPU_COUNT`, `GPU_UUIDS` не существует** — GPU
один, память общая. `nvidia-smi -L` и `CUDA_VISIBLE_DEVICES` применимы только к
классическому x86-DGX с несколькими картами.

---

## Шаги

### Шаг 1. Установить Ollama

```bash
curl -fsSL https://ollama.com/install.sh | sh
```

Ожидаемый результат: установщик отработал, `ollama` в `PATH`.

Если не так:
- Скачивание бинарника **работает из России без прокси** — маршрут проверен: `ollama.com/download/...` отдаёт 307-редирект на GitHub (`release-assets.githubusercontent.com`), а не на Cloudflare. Прокси на этом шаге не подключать.
- Модели через этот маршрут не пойдут — это Шаг 5.

Нужна конкретная версия:

```bash
curl -fsSL https://ollama.com/install.sh | OLLAMA_VERSION=0.32.0 sh
```

Ручная установка — **выбрать файл по `ARCH`, не по умолчанию**:

```bash
# aarch64 (DGX Spark / GB10) — проверено: 200 OK, ~1484 МБ
curl -fsSL https://ollama.com/download/ollama-linux-arm64.tar.zst \
    | sudo tar x -C /usr
```

```bash
# x86_64 (классический DGX) — ~1369 МБ
curl -fsSL https://ollama.com/download/ollama-linux-amd64.tar.zst \
    | sudo tar x -C /usr
```

Если не так: скачанный не под ту архитектуру бинарник не запустится. Сверить с `uname -m`.

Обновление поверх старой версии — сначала:

```bash
sudo rm -rf /usr/lib/ollama
```

### Шаг 1b. Проверить, что версия не древняя

```bash
ollama --version
```

Ожидаемый результат: версия близка к **v0.32.0**.
Если не так — версия вида `0.6.x`: **обновить перед тем, как продолжать.** На части
поставок предустановлена старая сборка, которая не грузит новые модели
([NemoClaw #4178](https://github.com/NVIDIA/NemoClaw/issues/4178)). Симптом выглядит как
«модель битая», причина — версия движка.

### Шаг 2. Создать пользователя службы

```bash
sudo useradd -r -s /bin/false -U -m -d /usr/share/ollama ollama
sudo usermod -a -G ollama $(whoami)
```

Ожидаемый результат: команды завершились без ошибок.

Если не так: `useradd` сообщает, что пользователь `ollama` уже существует → пропустить `useradd`, выполнить только `usermod`.

### Шаг 3. Создать unit-файл

Записать `/etc/systemd/system/ollama.service` ровно с этим содержимым:

```bash
sudo tee /etc/systemd/system/ollama.service > /dev/null <<'EOF'
[Unit]
Description=Ollama Service
After=network-online.target

[Service]
ExecStart=/usr/bin/ollama serve
User=ollama
Group=ollama
Restart=always
RestartSec=3
Environment="PATH=$PATH"
Environment="OLLAMA_CONTEXT_LENGTH=64000"

[Install]
WantedBy=multi-user.target
EOF
```

Ожидаемый результат: файл записан.

**`OLLAMA_CONTEXT_LENGTH=64000` не убирать.** Её нет в официальном примере, она добавлена осознанно:
- По умолчанию Ollama даёт контекст **всего 4096 токенов** при небольшом объёме памяти, а доки Ollama говорят: *«coding tools should be set to at least 64000 tokens»* ([context-length.mdx](https://github.com/ollama/ollama/blob/main/docs/context-length.mdx)).
- **Hermes просто откажется стартовать** при контексте меньше 64000 — его доки называют это «источником путаницы №1».
- Цена: контекст занимает память **сверх** веса модели. На DGX Spark с ~119 ГБ запас огромный, это не ограничение. На машине поскромнее — учитывать (см. Матрицу).

### Шаг 4. Запустить службу

```bash
sudo systemctl daemon-reload
sudo systemctl enable ollama
sudo systemctl start ollama
sudo systemctl status ollama
```

Ожидаемый результат: `systemctl status ollama` → `active (running)`.

Если не так:

```bash
journalctl -e -u ollama
```

### Шаг 5. Модели: если `ollama pull` виснет на 0%

Симптом: `ollama pull` показывает 0% и не двигается.

Причина не в Ollama. `registry.ollama.ai` стоит за Cloudflare, а российские провайдеры (Ростелеком, МегаФон, МТС, Билайн) **с 9 июня 2025 режут любой контент из-за Cloudflare на первых 16 килобайтах** — об этом пишет [сам Cloudflare](https://blog.cloudflare.com/russian-internet-users-are-unable-to-access-the-open-internet/). Манифест модели в 16 КБ пролезает, блоб на 20 ГБ — никогда. Отсюда вечные 0%. Ровно это описано в [issue #11583](https://github.com/ollama/ollama/issues/11583), где автор подтверждает: помог VPN.

**Ollama не ограничивает по стране.** Никаких требований к стране у неё нет. Это домашние провайдеры не дают до неё дойти. Прокси здесь — не обход правил сервиса, а обход блокировки на пути к нему.

Настройка прокси:

```bash
sudo systemctl edit ollama.service
```

Добавить:

```ini
[Service]
Environment="HTTPS_PROXY=https://адрес-твоего-прокси"
```

Затем:

```bash
sudo systemctl restart ollama
```

Ожидаемый результат: `ollama pull` доходит до 100%.

Если не так:
- **Только `HTTPS_PROXY`. `HTTP_PROXY` не ставить** — прямое предупреждение из [docs/faq.mdx](https://github.com/ollama/ollama/blob/main/docs/faq.mdx):

  > Avoid setting `HTTP_PROXY`. Ollama does not use HTTP for model pulls, only HTTPS.
  > Setting `HTTP_PROXY` may interrupt client connections to the server.

  То есть `HTTP_PROXY` рвёт соединения клиентов с сервером — ставить его нельзя даже «на всякий случай».
- Если прокси с собственным сертификатом — его нужно поставить как системный.

### Шаг 6. Проверить, что GPU реально работают

```bash
ollama pull qwen3.5:4b
ollama ps
```

Ожидаемый результат: в колонке **`PROCESSOR`** — **`100% GPU`**.

Если не так: `CPU` или смесь вроде `48%/52% CPU/GPU` → драйвер старый или модель не поместилась → вернуться к Предусловиям.

### Шаг 6b. Померять скорость — на GB10 это обязательный шаг, не опциональный

```bash
ollama run gpt-oss:20b --verbose "Напиши функцию быстрой сортировки на Python"
```

Ожидаемый результат: в конце вывода `eval rate` **того же порядка**, что в
[официальных замерах Ollama на DGX Spark](https://ollama.com/blog/nvidia-spark-performance) —
для `gpt-oss:20b` там **58 tok/s**. Замеры сделаны на прошивке 580.95.05.

Если не так (в разы ниже): не списывать на «модель большая» и не идти дальше.
Проверить `ollama ps` → `100% GPU`, версию Ollama (Шаг 1b), и
[issue #13552](https://github.com/ollama/ollama/issues/13552) — деградация скорости
после 20–30 минут работы.

**Про несколько карт: на DGX Spark их нет.** GB10 — единый чип, GPU один.
`nvidia-smi -L` и `CUDA_VISIBLE_DEVICES` здесь неприменимы; не пытаться распределять
модель по картам. На классическом x86-DGX — применимы:

```bash
nvidia-smi -L                       # взять UUID карт
export CUDA_VISIBLE_DEVICES=GPU-xxxx,GPU-yyyy
```

UUID надёжнее номеров — номера могут переехать между перезагрузками.

### Шаг 7. Скачать модели по матрице

На DGX Spark: взять модели из раздела «Что ставить» (Матрица ниже) — выбор идёт по
**типу весов (MoE)**, а не по объёму памяти. На x86-DGX выбирать по VRAM одной карты.

Ожидаемый результат: каждый pull доходит до 100%.

Если не так: см. Шаг 5.

После установки — обязательно Шаг 6b (замер скорости). Модель, которая скачалась и
загрузилась, может выдавать 4 tok/s и быть непригодной. Формальные проверки этого не ловят.

---

## Матрица выбора модели

### Оговорки (сохранить, не выбрасывать)

- **ollama.com не публикует требования по памяти.** Только вес файла. Все цифры ниже — **вес весов модели**, проверенный прямым запросом к реестру. Реальный расход выше: `память ≈ вес + KV-кэш + накладные`.
- **Вес файла не говорит о скорости.** `gpt-oss:120b` (65.4 ГБ) вдвое тяжелее `ornith:35b-q8_0` (36.9 ГБ), но по замерам вчетверо быстрее. Решает тип весов (MoE или плотная), а не вес. Не ранжировать модели по размеру файла.
- **Все заявления «лучшая модель» — это слова вендоров.** Например, ornith заявляет SOTA по Terminal-Bench и SWE-Bench на своей же странице. Независимого подтверждения нет. «Топ» ниже — про соответствие железу и здравый смысл, а не про доказанное первенство.
- Каждый тег в списках проверен живым запросом к реестру — выдуманных нет.

### Модели, которые НЕ работают локально — не пытаться

Только тег `:cloud`, скачать нельзя: `glm-5.1`, `glm-5.2`, `minimax-m2.5`, `minimax-m2.7`,
`minimax-m3`, `kimi-k2.6`, `kimi-k2.7-code`, `deepseek-v4-flash`, `deepseek-v4-pro`,
`nemotron-3-ultra`, `gemini-3-flash-preview`.

### 🔥 Правило выбора на DGX Spark: MoE, а не размер

**Не выбирать модель по объёму памяти.** На GB10 памяти ~119 ГБ — влезет практически
что угодно. Ограничение в другом.

**Узкое место — пропускная способность памяти: [273 ГБ/с](https://docs.nvidia.com/dgx/dgx-spark/hardware.html).**
При генерации на каждый токен читаются все активные веса; потолок ≈ `273 / размер активных весов`.
Для сравнения (официальные цифры): [RTX 4090](https://images.nvidia.com/aem-dam/Solutions/geforce/ada/nvidia-ada-gpu-architecture.pdf) — 1008 ГБ/с (3.7×),
[H100 SXM](https://www.nvidia.com/en-us/data-center/h100/) — 3350 ГБ/с (12.3×).

[Официальные замеры Ollama на DGX Spark](https://ollama.com/blog/nvidia-spark-performance),
прошивка 580.95.05:

| Модель | Тип | Генерация, tok/s |
|---|---|---|
| gpt-oss **20B** | **MoE** | **58.3** |
| llama3.1 **8B** | плотная | 38.0 |
| **gpt-oss 120B** | **MoE** | **41.1** |
| gemma3 **12B** | плотная | 24.3 |
| gemma3 **27B** | плотная | 10.8 |
| qwen3 **32B** | плотная | 9.4 |
| llama3.1 **70B** | плотная | **4.4** |

**MoE на 120B быстрее плотной на 32B вчетверо.** У MoE на токен активна лишь часть весов —
барьер пропускной способности обходится. Это не ошибка замера, это архитектура.

> **Оговорка про перенос цифр:** замеры от октября 2025, модели там прошлого поколения
> (llama3.1, gemma3, qwen3). Рекомендованные ниже модели свежее и в этих замерах
> отсутствуют. Таблица доказывает **закономерность**, а не конкретные tok/s. Мерять
> самому — Шаг 6b.

### Что ставить (DGX Spark / GB10)

Брать MoE. Плотную — только мелкую.

| Роль | Команда | Вес | Тип |
|---|---|---|---|
| 🥇 Кодинг | `ollama pull qwen3-coder-next` | 51.7 ГБ | **MoE** |
| 🥈 Рассуждения | `ollama pull gpt-oss:120b` | 65.4 ГБ | **MoE**, замерена — 41 tok/s |
| 🥉 Быстрая | `ollama pull gpt-oss:20b` | 13.8 ГБ | **MoE**, замерена — 58 tok/s |

Альтернативы, тоже MoE: `qwen3.6:35b-a3b` (23.9 ГБ, 3B активных),
`north-mini-code-1.0` (18.6 ГБ, контекст 488K), `laguna-xs-2.1` (20.3 ГБ).

Памяти ~119 ГБ — влезут все три сразу. Выбор ограничен **не** объёмом.

### Свежие Qwen / Kimi: матрица «влезает» (проверено роем, 2026-07-22)

Правила: **влезает** ⇔ вес Q4 (≈ B·params × 0.5 ГБ) + контекст `< ~119 ГБ`; **скорость** ⇔
активные параметры / 273 ГБ/с (не общий размер).

| Модель | Всего/актив. | Тип | Q4 | Влезает | Ollama-тег |
|---|---|---|---|---|---|
| `qwen3.6:35b-a3b` | 35B/3B | MoE | ~24 ГБ | ✅ | [qwen3.6](https://ollama.com/library/qwen3.6/tags) · [HF](https://huggingface.co/Qwen/Qwen3.6-35B-A3B) |
| `qwen3.5:122b-a10b` | 122B/10B | MoE | ~81 ГБ | ✅ **только Q4** | [qwen3.5](https://ollama.com/library/qwen3.5/tags) |
| `qwen3-coder:30b` | 30B/3.3B | MoE | ~19 ГБ | ✅ | [qwen3-coder](https://ollama.com/library/qwen3-coder/tags) · [HF](https://huggingface.co/Qwen/Qwen3-Coder-30B-A3B-Instruct) |
| `qwen3-coder-next` | ~80B/3B | MoE | ~52 ГБ | ✅ | [qwen3-coder-next](https://ollama.com/library/qwen3-coder-next/tags) |
| `qwen3.6:27b` | 27B/27B | плотн. | ~17 ГБ | ✅ ~16 tok/s | [qwen3.6](https://ollama.com/library/qwen3.6/tags) · [HF](https://huggingface.co/Qwen/Qwen3.6-27B) |
| `qwen3-235b-a22b` | 235B/22B | MoE | ~142 ГБ | ❌ | — |
| `qwen3-coder:480b-a35b` | 480B/35B | MoE | ~290 ГБ | ❌ | [qwen3-coder](https://ollama.com/library/qwen3-coder/tags) |
| Kimi K2/K2.5/K2.6/K2.7 | ~1T/32B | MoE | ~500–600 ГБ | ❌ **cloud/API** | [K2.6](https://huggingface.co/moonshotai/Kimi-K2.6) · [NIM](https://build.nvidia.com/moonshotai/kimi-k2.6/modelcard) |
| `Kimi-VL-A3B` / Moonlight-16B-A3B | 16B/3B | MoE | ~8–10 ГБ | ✅ (лёгкий VL-класс) | [community](https://ollama.com/richardyoung/kimi-vl-a3b-thinking) |

**Флагман Kimi (K2.x) на GB10 не грузится ни при каком кванте** (~1T params, мин. билд
240–340 ГБ ≈ 2–5× бюджета) → удалённый эндпоинт, см. [02-claude-code-cloudru.md](02-claude-code-cloudru.md).
Мелкие плотные Qwen3 (`8b/14b/32b`) и `qwen3:30b-a3b` влезают тривиально.

> **NOT VERIFIED:** Qwen3.5/3.6 — post-cutoff (фев–апр 2026). Теги/размеры из
> [ollama.com/library](https://ollama.com/library/qwen3.6/tags) + [QwenLM](https://github.com/QwenLM/Qwen3.6),
> независимо не подтверждены. **Перед использованием: `ollama pull <тег> && ollama show <тег>`**
> — сверить активные параметры и размер. `qwen3.5:122b-a10b` — идентичность только по листингу
> Ollama (low confidence). Баг конкурентности qwen3.5: [#14621](https://github.com/ollama/ollama/issues/14621).

### Модель под задачу + русский

| Модель | Сценарий | Русский |
|---|---|---|
| `gpt-oss:120b` | оркестратор+рассуждения (41 tok/s) | ❌ не подтв. ([MMMLU](https://arxiv.org/html/2508.10925v1) без RU) |
| `gpt-oss:20b` | быстрый/дешёвый ход, роутинг | ❌ не подтв. |
| `qwen3-coder:30b` | агентное кодирование | ⚠️ мультиязычность = **языки программирования** |
| `qwen3:30b-a3b-thinking` | рассуждения на скорости MoE | ✅ ([блог Qwen3](https://qwenlm.github.io/blog/qwen3/)) |
| `qwen3:30b-a3b-instruct` | **русский диалог** + tool-calling | ✅ поимённо |
| `qwen3-vl:30b` | vision | частично |

**Для русского — `Qwen3-Instruct`, не coder/gpt-oss** (русский назван поимённо, 119 языков —
[блог](https://qwenlm.github.io/blog/qwen3/), [report](https://arxiv.org/abs/2505.09388)). Облачный
разбор — [12-cloud-brain-routing.md](12-cloud-brain-routing.md). NOT VERIFIED: независимых RU-бенчей
(MERA/ru_llm_arena) по флагманам 2026 нет → живой пробник.

### 🛠 Tool-calling в Ollama — баги рантайма (не весов), гейтят выбор

Симптом (жалоба пользователей): модель генерит вызов, но на подаче `role:"tool"` обратно — **пустой
ответ, цикл рвётся**. Это баги OpenAI-совместимого слоя Ollama (`/v1`), **до** шаблона; правкой
`TEMPLATE` НЕ лечится. Затронуты почти все версии до v0.32.x, фиксы не смёржены.

| Причина пустого ответа | Обход | Issue |
|---|---|---|
| assistant `content:""` + `tool_calls` в истории | слать `content:null` | [#14181](https://github.com/ollama/ollama/issues/14181) |
| assistant `content` И `tool_calls` (только `/v1`) | нативный `/api/chat` | [#9802](https://github.com/ollama/ollama/issues/9802) |
| thinking + tools → вызов внутри `<think>` | `think=false` с tools | [#10976](https://github.com/ollama/ollama/issues/10976) |
| молчаливый сброс при парс-фейле | tripwire: пусто+токены→retry | [#17274](https://github.com/ollama/ollama/issues/17274) |

Универсальный обход: **`/api/chat` вместо `/v1/chat/completions`** + `content:null` + `think=false` с tools + tripwire.

Надёжность по моделям: **`llama3.3`** ✅ дефолт (но без русского); **`qwen3.5:35b-a3b`** ✅ только Ollama ≥ v0.30 ([#14605](https://github.com/ollama/ollama/pull/14605)); **`gpt-oss:120b`** ✅ станд. имена ([#11759](https://github.com/ollama/ollama/pull/11759)); **`qwen3-coder:30b`** ⚠️ воркэраунд ([#16686](https://github.com/ollama/ollama/issues/16686)); **`qwen3:30b-a3b`** ⚠️ `think=false`; **`gpt-oss:20b`** ❌ произв. имена ([#11991](https://github.com/ollama/ollama/issues/11991)); **`qwen3.6:27b`** ❌ HTTP 500 ([#16383](https://github.com/ollama/ollama/issues/16383)); `qwen3.6:35b-a3b`/`qwen3-coder-next` — данных нет.

🛑 **Правило:** смоук-тест multi-turn tool-loop (вызов→`role:"tool"`→продолжение) ДО доверия модели. `OLLAMA_NUM_PARALLEL=1` на GB10 ([#14621](https://github.com/ollama/ollama/issues/14621)).

### Чего не ставить на GB10 без замера

| Модель | Вес | Риск |
|---|---|---|
| `devstral-2` | 74.9 ГБ | 123B; если плотная — будет очень медленной |
| `ornith:35b-q8_0` | 36.9 ГБ | плотная 32B по замерам даёт ~9 tok/s |
| `nemotron-3-super:120b` | 86.8 ГБ | тип весов не заявлен |

> **NOT VERIFIED:** плотные ли `devstral-2`, `ornith:35b`, `nemotron-3-super:120b` или MoE —
> на страницах моделей не указано. **Не угадывать.** Проверяется только замером (Шаг 6b):
> `<10` tok/s → модель плотная, для интерактивной работы на GB10 не годится.

**Совет «брать `q8_0`, раз память позволяет» на GB10 инвертируется.** Менее сжатая
модель = больше байт через шину = медленнее. Память позволяет, шина — нет. Совет
OpenClaw *«Always run the largest / full-size variant you can host»* писался для машин
с быстрой памятью; здесь применять его буквально — ошибка.

### Известные проблемы на DGX Spark ARM64

Баг-репорты, не документация — проверить актуальность перед применением:

- [#15318](https://github.com/ollama/ollama/issues/15318) — segfault при загрузке
  **gemma4:26b/31b** на DGX Spark ARM64.
- [#14621](https://github.com/ollama/ollama/issues/14621) — параллельные запросы к qwen3.5
  падают с SIGABRT; обход — `Parallel: 1`. **Учитывать:** несколько агентов, одновременно
  бьющих в Ollama, могут её ронять.
- [#13552](https://github.com/ollama/ollama/issues/13552) — деградация скорости после
  20–30 минут работы.

### Полный проверенный список

**Кодинг и общие:**

| Тег | Вес | Контекст | Заметки |
|---|---|---|---|
| `ornith:9b` | 5.6 ГБ | 256K | MIT, агентный кодинг |
| `ornith:35b` | 21.2 ГБ | 256K | |
| `ornith:35b-q8_0` | 36.9 ГБ | 256K | |
| `qwen3.6:27b` | 17.4 ГБ | 256K | |
| `qwen3.6:35b-a3b` | 23.9 ГБ | 256K | MoE, 3B активных → быстрая |
| `glm-4.7-flash` | 19.0 ГБ | 198K | |
| `north-mini-code-1.0` | 18.6 ГБ | **488K** | Cohere, 30B MoE |
| `laguna-xs-2.1` | 20.3 ГБ | 256K | 33B MoE |
| `qwen3-coder:30b` | 18.6 ГБ | — | |
| `devstral-2` | 74.9 ГБ | — | 123B, многофайловое редактирование |

**Рассуждения:**

| Тег | Вес | Контекст |
|---|---|---|
| `gpt-oss:20b` | 13.8 ГБ | 128K |
| `gpt-oss:120b` | 65.4 ГБ | 128K |
| `nemotron-cascade-2:30b` | 24.3 ГБ | 256K |
| `nemotron-3-super:120b` | 86.8 ГБ | 256K |

**Маленькие и быстрые:**

| Тег | Вес | Контекст |
|---|---|---|
| `lfm2.5-thinking:1.2b` | 0.7 ГБ | 125K |
| `qwen3.5:0.8b` | 1.0 ГБ | — |
| `granite4.1:3b` | 2.1 ГБ | 128K |
| `qwen3.5:4b` | 3.4 ГБ | — |
| `granite4.1:8b` | 5.3 ГБ | 128K |
| `qwen3.5:9b` | 6.6 ГБ | — |
| `gemma4:12b` | 7.6 ГБ | 256K |

---

## Что Ollama отдаёт наружу

Понадобится всем остальным инструкциям.

| Протокол | Адрес | Кто использует |
|---|---|---|
| **Anthropic-совместимый** | `http://localhost:11434` → `/v1/messages` | Claude Code |
| **OpenAI-совместимый** | `http://localhost:11434/v1` | Hermes, Ouroboros |
| **OpenAI-совместимый, но БЕЗ `/v1`** | `http://127.0.0.1:11434` | **OpenClaw** — см. ловушку ниже |
| Родной Ollama | `http://localhost:11434/api` | сам `ollama` |

Источники: [anthropic-compatibility.mdx](https://github.com/ollama/ollama/blob/main/docs/api/anthropic-compatibility.mdx),
[openai-compatibility.mdx](https://github.com/ollama/ollama/blob/main/docs/api/openai-compatibility.mdx).

🛑 **NemoClaw в таблице отсутствует намеренно — не дописывать.** Он адрес Ollama **не
принимает**: достаточно `NEMOCLAW_PROVIDER=ollama` ([03-nemoclaw.md](03-nemoclaw.md)),
URL в рецепте нигде не задаётся. Плюс агент, которого NemoClaw запускает по умолчанию, —
OpenClaw, которому `/v1` **ломает вызов инструментов**. Строка «NemoClaw → с `/v1`» была бы
и лишней, и вредной.

**Не сопоставлять адрес по шаблону с соседней строкой таблицы.** Суффикс у каждого агента
свой, и ошибка тихая: выглядит как «модель тупая», а не как ошибка конфигурации.

По умолчанию Ollama слушает только `127.0.0.1`. Открыть по сети (**только в доверенной
сети** — авторизации там нет):

```bash
Environment="OLLAMA_HOST=0.0.0.0:11434"
```

⚠️ **Отдельная ловушка для OpenClaw:** ему нужен адрес **без** `/v1`. Его доки предупреждают,
что через `/v1` ломается вызов инструментов. Подробности — в [06-openclaw.md](06-openclaw.md).

---

## Стоп-условия

Не делать. Остановиться и спросить человека:

1. **Драйвер старее 550** — не устанавливать поверх, не «пробовать всё равно». Обновление драйвера — вопрос к человеку.
2. **Compute capability ниже 5.0** — не продолжать.
3. **Не ставить `HTTP_PROXY`** ни при каких симптомах. Только `HTTPS_PROXY` (рвёт клиентские соединения — см. Шаг 5).
4. **Не убирать и не понижать `OLLAMA_CONTEXT_LENGTH=64000`** — Hermes не стартует ниже этого значения.
5. **`PROXY_URL` не подбирать и не угадывать** — брать у человека. Если прокси нужен (pull виснет на 0%), а адреса нет — остановиться.
6. **Системный сертификат прокси** — если прокси с собственным сертификатом, установка сертификата в систему требует решения человека.
7. **`sudo systemctl edit ollama.service` открывает интерактивный редактор.** Неинтерактивного варианта в исходной инструкции нет. Если редактор запустить нельзя — остановиться и спросить, а не изобретать обходной путь.
8. **Не подставлять архитектуру по названию машины.** «DGX» ≠ x86_64: у DGX Spark процессор Arm, `uname -m` → `aarch64`. Только по `uname -m`, иначе скачается бинарник, который не запустится.
9. **`Memory-Usage: Not Supported` на GB10 — не ошибка.** [Задокументировано NVIDIA](https://docs.nvidia.com/dgx/dgx-spark/known-issues.html) как ожидаемое поведение iGPU без выделенного фреймбуфера. Не чинить, не откатывать драйвер, не сообщать человеку как о проблеме. Память читать через `free -g`.
10. **Не выбирать модель по объёму памяти на GB10.** Влезет почти всё; решает пропускная способность (273 ГБ/с) и тип весов. Выбор по размеру даст формально успешную установку на 4 tok/s.
11. **Тип весов (MoE/плотная) не угадывать.** Если на странице модели не заявлено — пометить `NOT VERIFIED` и мерять (Шаг 6b), а не предполагать.
12. **Модели с тегом `:cloud`** (список выше) — не пытаться скачать, локально не работают.
13. **`OLLAMA_HOST=0.0.0.0:11434`** — не включать самовольно: авторизации нет, только доверенная сеть, решение человека.
14. **Установка со скоростью в разы ниже [официальных замеров](https://ollama.com/blog/nvidia-spark-performance) — не «готово».** Не выдавать её за рабочую: предупредить человека и назвать полученный `eval rate`.

---

## Критерий готовности

Единый проверочный блок. Успех — если напечатано `ALL CHECKS PASSED`.

```bash
set -u
FAIL=0

# 1. ollama --version печатает версию
ollama --version && echo "OK 1" || { echo "FAIL 1: ollama --version"; FAIL=1; }

# 2. systemctl status ollama — active (running)
systemctl is-active ollama | grep -qx active \
  && echo "OK 2" || { echo "FAIL 2: ollama not active (running)"; FAIL=1; }

# 3. ollama ps показывает 100% GPU в колонке PROCESSOR
ollama ps | grep -q "100% GPU" \
  && echo "OK 3" || { echo "FAIL 3: PROCESSOR != 100% GPU"; FAIL=1; }

# 4. ollama pull доходит до 100%, а не виснет на 0%
ollama pull qwen3.5:4b \
  && echo "OK 4" || { echo "FAIL 4: pull failed/stalled"; FAIL=1; }

# 5. curl отдаёт JSON со списком моделей
curl -fsS http://localhost:11434/api/tags | grep -q '"models"' \
  && echo "OK 5" || { echo "FAIL 5: /api/tags"; FAIL=1; }

# 6. OLLAMA_CONTEXT_LENGTH=64000 реально в конфиге службы
systemctl show ollama -p Environment | grep -q "OLLAMA_CONTEXT_LENGTH=64000" \
  && echo "OK 6" || { echo "FAIL 6: OLLAMA_CONTEXT_LENGTH != 64000"; FAIL=1; }

# 7. HTTP_PROXY НЕ выставлен для службы
#    (HTTPS_PROXY= не совпадёт: после HTTP идёт S, а не _)
systemctl show ollama -p Environment | grep -q "HTTP_PROXY=" \
  && { echo "FAIL 7: HTTP_PROXY is set — remove it"; FAIL=1; } || echo "OK 7"

# 8. Версия не древняя (0.6.x не грузит новые модели)
ollama --version | grep -qE "0\.(6|[0-9])\." \
  && { echo "WARN 8: проверить версию вручную, ожидается ~0.32"; } || echo "OK 8"

[ "$FAIL" -eq 0 ] && echo "ALL CHECKS PASSED" || echo "CHECKS FAILED"
```

**Этот блок не проверяет главного — скорости.** Он пройдёт целиком на установке, выдающей
4 tok/s. Замер (Шаг 6b) машиной не проверяется: сверить `eval rate` с
[официальными замерами](https://ollama.com/blog/nvidia-spark-performance) должен человек
или ты глазами.

Чек-лист (то же словами):

- [ ] `uname -m` выполнен, бинарник скачан под эту архитектуру
- [ ] `ollama --version` печатает версию, и она не `0.6.x`
- [ ] `systemctl status ollama` — `active (running)`
- [ ] `ollama ps` показывает `100% GPU` в колонке `PROCESSOR`
- [ ] `ollama pull` доходит до 100%, а не виснет на 0%
- [ ] `curl http://localhost:11434/api/tags` отдаёт JSON со списком моделей
- [ ] `OLLAMA_CONTEXT_LENGTH=64000` в окружении службы
- [ ] `HTTP_PROXY` не выставлен
- [ ] **`eval rate` того же порядка, что в официальных замерах** (Шаг 6b)

На GB10 `Memory-Usage: Not Supported` в `nvidia-smi` — норма, в чек-лист не входит и
проблемой не является.

Дальше: [01-claude-code-local.md](01-claude-code-local.md) — подключить Claude Code
к поднятому движку.
