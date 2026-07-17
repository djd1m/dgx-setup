# 00. Ollama на DGX + какие модели ставить

Ollama — движок, который запускает языковые модели на твоём GPU. Это фундамент: все
остальные агенты из этого репозитория обращаются к нему на `localhost`. Ставим первым.

**Инструкция написана под DGX Spark / GB10 (`aarch64`)** — включая OEM-версии вроде
[Dell Pro Max with GB10](https://www.dell.com/en-us/shop/desktop-computers/dell-pro-max-with-gb10/spd/dell-pro-max-fcm1253-micro).
Для классического x86-DGX с отдельными картами A100/H100 она тоже годится, но два места
придётся читать критически: **бинарник** (Шаг 1) и **выбор моделей** — там всё завязано
на особенность GB10, которой у обычных карт нет. Шаг 0 разведёт эти случаи.

Официальные источники: [ollama.com/download/linux](https://ollama.com/download/linux),
[github.com/ollama/ollama](https://github.com/ollama/ollama),
[матрица поддержки GPU](https://docs.ollama.com/gpu).
Актуальная версия на момент написания — **v0.32.0** (11 июля 2026).

---

## Шаг 0. Понять, какая у тебя машина

**Сделай это до установки.** «DGX» — это семейство, а не одна машина, и они бывают
**разной архитектуры процессора**. Ошибёшься здесь — скачаешь бинарник, который не запустится.

```bash
uname -m
nvidia-smi
free -g
```

### Главная развилка: `aarch64` или `x86_64`

| `uname -m` | Что это | Эта инструкция |
|---|---|---|
| **`aarch64`** | DGX Spark / GB10 и OEM-версии (Dell Pro Max with GB10, HP, Lenovo, ASUS…) | ✅ **написана под неё** |
| `x86_64` | классический DGX с отдельными картами (A100/H100) | ⚠️ подойдёт в целом, но бинарник бери `amd64`, а раздел про модели читай критически |

У **DGX Spark** внутри чип [GB10 Grace Blackwell](https://docs.nvidia.com/dgx/dgx-spark/hardware.html):
20 ядер Arm (10 Cortex-X925 + 10 Cortex-A725). Grace — это **Arm**, поэтому `aarch64`.
Штатная ОС — [DGX OS 7](https://docs.nvidia.com/dgx/dgx-os-7-user-guide/introduction.html),
это кастомизированная Ubuntu 24.04 под arm64.

Машину могут продавать под чужим брендом: например,
[Dell Pro Max with GB10](https://www.dell.com/en-us/shop/desktop-computers/dell-pro-max-with-gb10/spd/dell-pro-max-fcm1253-micro)
(модель FCM1253) — то же железо, логотип Dell на загрузке. Проверить, что у тебя:

```bash
cat /sys/class/dmi/id/product_name /sys/class/dmi/id/sys_vendor
```

> **NOT VERIFIED:** что «Dell Pro Max with GB10» — это официально OEM-версия DGX Spark.
> Dell на своих страницах слово «DGX Spark» **не употребляет**, называет продукт
> «AI Accelerator». Но спецификации совпадают до цифры, ОС та же DGX OS, а NVIDIA
> [прямо называет Dell партнёром по производству DGX Spark](https://nvidianews.nvidia.com/news/nvidia-announces-dgx-spark-and-dgx-station-personal-ai-computers).
> Практический вывод: всё, что написано для DGX Spark, к этой машине применимо.

### Драйвер

| Что | Требование | Где смотреть |
|---|---|---|
| Версия драйвера | **550 или новее** | `nvidia-smi`, верхняя строка, `Driver Version:` |
| Compute capability | **5.0 или выше** | у GB10 — **12.1**, проходит с запасом |

Источник требований: [docs.ollama.com/gpu](https://docs.ollama.com/gpu). GB10 там
**перечислен явно** — строка `12.1 | NVIDIA | GB10 (DGX Spark)`. То есть поддержка не
случайная: у Ollama с NVIDIA [партнёрство под эту машину](https://ollama.com/blog/nvidia-spark),
заявлено «runs fast and efficiently out-of-the-box».

**Если драйвер старее 550** — Ollama не увидит GPU и молча уйдёт считать на процессоре.
Работать будет, но в десятки раз медленнее. На штатной DGX OS драйвер свежий, проблемы быть не должно.

### 🛑 `Memory-Usage: Not Supported` — это норма, не поломка

На GB10 `nvidia-smi` покажет в колонке памяти `Not Supported`. **Ничего не сломалось.**
Дословно из [Known Issues DGX Spark](https://docs.nvidia.com/dgx/dgx-spark/known-issues.html):

> On iGPU platforms, nvidia-smi will display "Memory-Usage: Not Supported" even though
> per-process GPU memory is listed. **This is expected** because iGPUs do not have
> dedicated framebuffer memory.

Причина в устройстве машины: у GB10 **нет отдельной видеопамяти**. Память
**единая (unified)** — CPU и GPU делят один физический пул, связанный через NVLink-C2C.
Показывать в колонке «Memory-Usage» просто нечего.

**Поэтому память смотри через `free`, а не через `nvidia-smi`:**

```bash
free -g
```

Ожидается около **119 ГБ** из 128 номинальных (2 ГБ забирает дисплей — это
[документированный carveout](https://docs.nvidia.com/dgx/dgx-spark/dgx-spark.pdf),
в BIOS переключается на 4 ГБ; остальное — ОС).

Ключевые цифры GB10 из [Table 1 User Guide](https://docs.nvidia.com/dgx/dgx-spark/hardware.html):

| Параметр | Значение |
|---|---|
| Память | **128 ГБ LPDDR5x unified**, 256-бит |
| Пропускная способность | **273 ГБ/с** |
| CUDA-ядер | 6 144 |
| TDP чипа | 140 Вт |

Число **273 ГБ/с** запомни — в разделе про выбор моделей окажется, что именно оно,
а не объём, определяет, что тут реально работает.

> **NOT VERIFIED:** сколько именно памяти доступно GPU под модель. NVIDIA такого числа
> не публикует — при единой памяти распределение динамическое. Практически это
> ~128 минус 2 (дисплей) минус ОС. Отдельная официальная оговорка из Known Issues:
> `cudaMemGetInfo` **занижает** доступную память, потому что не учитывает страницы в SWAP.

---

## Шаг 1. Установить Ollama

```bash
curl -fsSL https://ollama.com/install.sh | sh
```

Хорошая новость: **этот шаг работает из России без прокси.** Я проверил маршрут —
`ollama.com/download/...` отдаёт 307-редирект на GitHub (`release-assets.githubusercontent.com`),
а не на Cloudflare. Так что бинарник скачается.

А вот модели — не скачаются. Об этом Шаг 3.

### Ручная установка (и как не скачать не тот бинарник)

Скрипт `install.sh` определяет архитектуру сам. Но если ставишь руками — **выбери верный файл**:

```bash
# aarch64 (DGX Spark / GB10) — проверено, 200 OK, ~1484 МБ
curl -fsSL https://ollama.com/download/ollama-linux-arm64.tar.zst \
    | sudo tar x -C /usr
```

```bash
# x86_64 (классический DGX) — ~1369 МБ
curl -fsSL https://ollama.com/download/ollama-linux-amd64.tar.zst \
    | sudo tar x -C /usr
```

Ошибёшься архитектурой — бинарник не запустится. Сверься с `uname -m` из Шага 0.

Обновляешь поверх старой версии — сначала `sudo rm -rf /usr/lib/ollama`.

> ⚠️ **Проверь версию, даже если Ollama уже стоит.** На части поставок предустановлена
> старая сборка, которая не грузит новые модели — например, `0.6.2`
> ([NemoClaw #4178](https://github.com/NVIDIA/NemoClaw/issues/4178)). `ollama --version`,
> и если версия старая — обнови, не воюй с симптомами.

Нужна конкретная версия:

```bash
curl -fsSL https://ollama.com/install.sh | OLLAMA_VERSION=0.32.0 sh
```

---

## Шаг 2. Запустить как системную службу

Чтобы Ollama поднималась сама после перезагрузки.

```bash
sudo useradd -r -s /bin/false -U -m -d /usr/share/ollama ollama
sudo usermod -a -G ollama $(whoami)
```

Создай файл `/etc/systemd/system/ollama.service`:

```ini
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
```

Запусти:

```bash
sudo systemctl daemon-reload
sudo systemctl enable ollama
sudo systemctl start ollama
sudo systemctl status ollama
```

Логи, если что-то не так: `journalctl -e -u ollama`

### Про `OLLAMA_CONTEXT_LENGTH=64000` — не убирай эту строку

Её нет в официальном примере, она добавлена осознанно. По умолчанию Ollama даёт
контекст **всего 4096 токенов** при небольшом объёме памяти, а сами доки Ollama говорят:
*«coding tools should be set to at least 64000 tokens»*
([context-length.mdx](https://github.com/ollama/ollama/blob/main/docs/context-length.mdx)).

Более того, **Hermes просто откажется стартовать** при контексте меньше 64000 — его доки
называют это «источником путаницы №1». Так что выставляем сразу и забываем.

Цена: контекст занимает память **сверх** веса модели. На DGX Spark с его ~119 ГБ это
не проблема — запас огромный. На машине поскромнее учитывай при выборе размера.

---

## Шаг 3. Модели: почему `ollama pull` виснет на 0% и что делать

Симптом: `ollama pull` показывает 0% и не двигается.

Причина не в Ollama. `registry.ollama.ai` стоит за Cloudflare, а российские провайдеры
(Ростелеком, МегаФон, МТС, Билайн) **с 9 июня 2025 режут любой контент из-за Cloudflare
на первых 16 килобайтах** — об этом пишет [сам Cloudflare](https://blog.cloudflare.com/russian-internet-users-are-unable-to-access-the-open-internet/).
Манифест модели в 16 КБ пролезает, блоб на 20 ГБ — никогда. Отсюда вечные 0%.
Ровно это описано в [issue #11583](https://github.com/ollama/ollama/issues/11583),
где автор подтверждает: помог VPN.

Подчеркну: **Ollama тебя не ограничивает.** Никаких требований к стране у неё нет.
Это домашние провайдеры не дают до неё дойти. Поэтому прокси здесь — не обход правил
сервиса, а обход блокировки на пути к нему.

### Настройка прокси для Ollama

```bash
sudo systemctl edit ollama.service
```

Добавь:

```ini
[Service]
Environment="HTTPS_PROXY=https://адрес-твоего-прокси"
```

Затем:

```bash
sudo systemctl restart ollama
```

**Только `HTTPS_PROXY`. `HTTP_PROXY` не ставь.** Это прямое предупреждение из
[docs/faq.mdx](https://github.com/ollama/ollama/blob/main/docs/faq.mdx):

> Avoid setting `HTTP_PROXY`. Ollama does not use HTTP for model pulls, only HTTPS.
> Setting `HTTP_PROXY` may interrupt client connections to the server.

Если прокси с собственным сертификатом — его нужно поставить как системный.

---

## Шаг 4. Проверить, что GPU реально работают

Скачай что-нибудь маленькое и посмотри:

```bash
ollama pull qwen3.5:4b
ollama ps
```

В колонке **`PROCESSOR`** должно быть **`100% GPU`**. Если там `CPU` или смесь вроде
`48%/52% CPU/GPU` — драйвер старый или модель не поместилась. Вернись к Шагу 0.

Заодно померяй скорость — на GB10 это важнее, чем где-либо:

```bash
ollama run gpt-oss:20b --verbose "Напиши функцию быстрой сортировки на Python"
```

В конце вывода будет `eval rate` — токенов в секунду. Сверься с
[замерами Ollama на DGX Spark](https://ollama.com/blog/nvidia-spark-performance): для
`gpt-oss:20b` там 58 tok/s. Получил близко — всё в порядке. Получил в разы меньше —
что-то не так, и это не «модель большая».

**Про несколько карт: на DGX Spark их нет.** GB10 — единый чип, GPU один. Всё, что
написано в интернете про `CUDA_VISIBLE_DEVICES` и распределение модели по картам, к этой
машине не относится. На классическом x86-DGX с несколькими A100/H100 — относится:

```bash
nvidia-smi -L                       # взять UUID карт
export CUDA_VISIBLE_DEVICES=GPU-xxxx,GPU-yyyy
```

UUID надёжнее номеров — номера могут переехать между перезагрузками.

---

## Какие модели ставить

### Сначала — честная оговорка

**ollama.com не публикует требования по памяти.** Только вес файла. Все цифры ниже — это
**вес весов модели**, проверенный прямым запросом к реестру. Реальный расход выше:
`память ≈ вес + KV-кэш + накладные`. При контексте 64k добавляй заметный запас.

И главное для GB10: **вес файла ничего не говорит о скорости.** По весу `gpt-oss:120b`
(65.4 ГБ) выглядит вдвое тяжелее `ornith:35b-q8_0` (36.9 ГБ) — а работает,
по замерам, вчетверо быстрее. Решает архитектура (MoE или плотная), а не вес.

Ещё: **все заявления «лучшая модель» — это слова вендоров.** Например, ornith заявляет
SOTA по Terminal-Bench и SWE-Bench на своей же странице. Независимого подтверждения нет.
Так что «топ» ниже — это про соответствие железу и здравый смысл, а не про доказанное первенство.

### Модели, которые НЕ работают локально

Не трать время: у них есть только тег `:cloud`, скачать нельзя. Это `glm-5.1`, `glm-5.2`,
`minimax-m2.5`, `minimax-m2.7`, `minimax-m3`, `kimi-k2.6`, `kimi-k2.7-code`, `deepseek-v4-flash`,
`deepseek-v4-pro`, `nemotron-3-ultra`, `gemini-3-flash-preview`.

### 🔥 На DGX Spark главное — не размер модели, а MoE

Это самый важный раздел инструкции, и он противоречит здравому смыслу.

**Узкое место GB10 — не объём памяти, а её пропускная способность: 273 ГБ/с.**
Для сравнения, все цифры официальные:

| GPU | Пропускная способность | Отношение к GB10 |
|---|---|---|
| **GB10** | **273 ГБ/с** | 1× |
| [RTX 4090](https://images.nvidia.com/aem-dam/Solutions/geforce/ada/nvidia-ada-gpu-architecture.pdf) | 1008 ГБ/с | 3.7× быстрее |
| [A100 80GB SXM](https://www.nvidia.com/content/dam/en-zz/Solutions/Data-Center/a100/pdf/nvidia-a100-datasheet-us-nvidia-1758950-r4-web.pdf) | 2039 ГБ/с | 7.5× |
| [H100 SXM](https://www.nvidia.com/en-us/data-center/h100/) | 3350 ГБ/с | 12.3× |

Почему это решает всё: при генерации на **каждый токен** читаются все активные веса модели.
Потолок скорости ≈ `пропускная способность / размер активных весов`. Вычислительная мощность
тут ни при чём — упор в шину.

### Официальные замеры на этом же железе

Считать не нужно — [Ollama опубликовала замеры на DGX Spark](https://ollama.com/blog/nvidia-spark-performance),
причём на прошивке **580.95.05**. Смотри на аномалию:

| Модель | Тип | Квант. | Генерация, tok/s |
|---|---|---|---|
| gpt-oss **20B** | **MoE** | MXFP4 | **58.3** |
| llama3.1 **8B** | плотная | q4_K_M | 38.0 |
| **gpt-oss 120B** | **MoE** | MXFP4 | **41.1** |
| gemma3 **12B** | плотная | q4_K_M | 24.3 |
| deepseek-r1 **14B** | плотная | q4_K_M | 20.0 |
| gemma3 **27B** | плотная | q4_K_M | 10.8 |
| qwen3 **32B** | плотная | q4_K_M | 9.4 |
| llama3.1 **70B** | плотная | q4_K_M | **4.4** |

**Модель на 120B работает вчетверо быстрее модели на 32B.** Это не опечатка и не ошибка замера.

Причина: у **MoE** (Mixture of Experts) на каждый токен активна лишь малая часть весов.
Модель целиком лежит в памяти — но через шину на каждый токен едет немного. Плотная 70B
тащит через шину всё, поэтому и даёт 4.4 tok/s: медленнее, чем ты читаешь.

**Вывод, который и надо унести:** GB10 покупают за **объём**, а не за скорость. Он запускает
то, что в RTX 4090 не влезет физически, — просто небыстро. А **MoE-модели превращают его
слабость в силу**: они и большие, и быстрые одновременно.

> **Оговорка про перенос цифр.** Замеры Ollama — от октября 2025, там модели предыдущего
> поколения (llama3.1, gemma3, qwen3). Модели ниже — свежее, и их в этих замерах нет.
> Так что таблица доказывает **закономерность** (MoE против плотной, порядок скорости на
> размер), а не конкретные tok/s для рекомендованных моделей. Свои цифры меряй сам.

### Что ставить на DGX Spark

Правило простое: **бери MoE. Плотную — только если она мелкая.**

| Роль | Модель | Вес | Почему |
|---|---|---|---|
| 🥇 Кодинг | `ollama pull qwen3-coder-next` | 51.7 ГБ | **MoE**, специализирована на кодинге |
| 🥈 Рассуждения | `ollama pull gpt-oss:120b` | 65.4 ГБ | **MoE**, замерена на этом железе — **41 tok/s** |
| 🥉 Быстрая | `ollama pull gpt-oss:20b` | 13.8 ГБ | **MoE**, замерена — **58 tok/s**, самая шустрая |

Ещё MoE, если хочется альтернатив: `qwen3.6:35b-a3b` (23.9 ГБ, 3B активных),
`north-mini-code-1.0` (18.6 ГБ, контекст 488K), `laguna-xs-2.1` (20.3 ГБ).

Памяти у тебя ~119 ГБ, так что влезет **любая** из них — и даже две сразу. Ограничение
не в объёме.

### Чего на этой машине лучше не брать

| Модель | Вес | Почему |
|---|---|---|
| `devstral-2` | 74.9 ГБ | 123B, влезет — но если плотная, будет очень медленной |
| `ornith:35b-q8_0` | 36.9 ГБ | по замерам плотная 32B даёт ~9 tok/s |
| `nemotron-3-super:120b` | 86.8 ГБ | влезет, но тип весов неизвестен |

> **NOT VERIFIED:** являются ли `devstral-2`, `ornith:35b`, `nemotron-3-super:120b` плотными
> или MoE — на страницах моделей это не заявлено. Проверить можно только замером:
> поставь и посмотри tok/s. Если получишь &lt;10 tok/s — модель плотная, и на GB10 она
> не для интерактивной работы.

### ⚠️ Два совета из документации, которые на GB10 инвертируются

**«Бери менее сжатую, раз память позволяет» (`q8_0`).** Менее сжатая модель = больше байт
через шину = медленнее. Память позволяет, а шина — нет.

**«Always run the largest / full-size variant you can host»** — это дословная цитата из
[документации OpenClaw](https://docs.openclaw.ai/gateway/local-models), и её ты встретишь
снова в [06-openclaw.md](06-openclaw.md). **Буквально на этой машине применять её нельзя:**
она писалась для железа с быстрой памятью. «Крупнейшая, что влезла» здесь — это плотная
70B на 4.4 tok/s.

Что за ней стоит на самом деле — требование **сильной** модели (слабой опасно давать
инструменты). На GB10 оно выполняется через **MoE**: `gpt-oss:120b` силён как 120B и даёт
41 tok/s. **Бери MoE покрупнее, а не плотную покрупнее.**

### Известные проблемы именно на DGX Spark ARM64

Это баг-репорты, не документация — статус меняется, проверяй актуальность:

- [#15318](https://github.com/ollama/ollama/issues/15318) — segfault при загрузке
  **gemma4:26b/31b** на DGX Spark ARM64. При этом Nemotron 3 Super 120B, Qwen 3.5 35B
  и Qwen 2.5 72B в том же отчёте работают.
- [#14621](https://github.com/ollama/ollama/issues/14621) — параллельные запросы к qwen3.5
  падают с SIGABRT. Обход — принудительно `Parallel: 1`. **Важно для агентов:** несколько
  агентов, бьющих в Ollama одновременно, могут ронять её.
- [#13552](https://github.com/ollama/ollama/issues/13552) — деградация скорости после
  20–30 минут работы.

### Полный проверенный список

Каждый тег проверен живым запросом к реестру — выдуманных здесь нет.

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

Это понадобится всем остальным инструкциям.

| Протокол | Адрес | Кто использует |
|---|---|---|
| **Anthropic-совместимый** | `http://localhost:11434` → `/v1/messages` | Claude Code |
| **OpenAI-совместимый** | `http://localhost:11434/v1` | Hermes, Ouroboros |
| **OpenAI-совместимый, но БЕЗ `/v1`** | `http://127.0.0.1:11434` | **OpenClaw** — см. ловушку ниже |
| Родной Ollama | `http://localhost:11434/api` | сам `ollama` |

Источники: [anthropic-compatibility.mdx](https://github.com/ollama/ollama/blob/main/docs/api/anthropic-compatibility.mdx),
[openai-compatibility.mdx](https://github.com/ollama/ollama/blob/main/docs/api/openai-compatibility.mdx).

**NemoClaw в таблице нет намеренно.** Он адрес Ollama **не спрашивает** — достаточно
`NEMOCLAW_PROVIDER=ollama` ([03-nemoclaw.md](03-nemoclaw.md)). А агент, которого он запускает
по умолчанию, — OpenClaw, то есть строка «с `/v1`» была бы для него ещё и вредна.

По умолчанию Ollama слушает только `127.0.0.1`. Открыть по сети (**только в доверенной
сети** — авторизации там нет):

```bash
Environment="OLLAMA_HOST=0.0.0.0:11434"
```

⚠️ **Отдельная ловушка для OpenClaw:** ему нужен адрес **без** `/v1`. Его доки предупреждают,
что через `/v1` ломается вызов инструментов. Подробности — в [06-openclaw.md](06-openclaw.md).

---

## Готово, если

- [ ] `uname -m` — знаешь свою архитектуру, и бинарник скачан под неё
- [ ] `ollama --version` печатает версию, и она **не** старая (не `0.6.x`)
- [ ] `systemctl status ollama` — `active (running)`
- [ ] `ollama ps` показывает `100% GPU` в колонке `PROCESSOR`
- [ ] `ollama pull` доходит до 100%, а не виснет на 0%
- [ ] `curl http://localhost:11434/api/tags` отдаёт JSON со списком моделей
- [ ] **`ollama run … --verbose` даёт `eval rate` того же порядка, что в
      [замерах на DGX Spark](https://ollama.com/blog/nvidia-spark-performance)**

Последний пункт — единственный, который проверяет то, ради чего всё затевалось. Модель
может «работать» на 3 tok/s и формально проходить все проверки выше. Если скорость
в разы ниже официальных замеров — ищи причину сразу, а не после того, как подключишь
пять агентов.

На GB10 `Memory-Usage: Not Supported` в `nvidia-smi` — **норма**, в этот пункт не входит.

Дальше: [01-claude-code-local.md](01-claude-code-local.md) — подключить Claude Code
к тому, что ты только что поднял.
