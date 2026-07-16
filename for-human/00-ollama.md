# 00. Ollama на DGX + какие модели ставить

Ollama — движок, который запускает языковые модели на твоих GPU. Это фундамент: все
остальные агенты из этого репозитория обращаются к нему на `localhost`. Ставим первым.

Официальные источники: [ollama.com/download/linux](https://ollama.com/download/linux),
[github.com/ollama/ollama](https://github.com/ollama/ollama).
Актуальная версия на момент написания — **v0.32.0** (11 июля 2026).

---

## Шаг 0. Проверить, что железо потянет

**Сделай это до установки.** У Ollama жёсткие требования к GPU, и если их не выполнить,
ты потратишь час на догадки, почему всё тормозит.

```bash
nvidia-smi
```

Смотри на две вещи:

| Что | Требование | Где смотреть |
|---|---|---|
| Версия драйвера | **550 или новее** | верхняя строка вывода, `Driver Version:` |
| Compute capability | **5.0 или выше** | см. таблицу ниже |
| Объём VRAM | запомни цифру | колонка `Memory-Usage`, правое число |

Источник требований: [docs/gpu.mdx](https://github.com/ollama/ollama/blob/main/docs/gpu.mdx).

Compute capability для типичных карт в DGX — все проходят с запасом:

| GPU | Compute capability | Годится |
|---|---|---|
| V100 | 7.0 | ✅ |
| A100 | 8.0 | ✅ |
| H100 / H200 | 9.0 | ✅ |

**Если драйвер старее 550** — Ollama не увидит GPU и молча уйдёт считать на процессоре.
Это будет работать, но в десятки раз медленнее. Обновляй драйвер до установки.

Сколько у тебя карт, тоже посмотри — в DGX их обычно 4 или 8, и это меняет выбор модели:

```bash
nvidia-smi -L
```

---

## Шаг 1. Установить Ollama

```bash
curl -fsSL https://ollama.com/install.sh | sh
```

Хорошая новость: **этот шаг работает из России без прокси.** Я проверил маршрут —
`ollama.com/download/...` отдаёт 307-редирект на GitHub (`release-assets.githubusercontent.com`),
а не на Cloudflare. Так что бинарник скачается.

А вот модели — не скачаются. Об этом Шаг 3.

### Если нужна установка без интернета

```bash
curl -fsSL https://ollama.com/download/ollama-linux-amd64.tar.zst \
    | sudo tar x -C /usr
```

Обновляешь поверх старой версии — сначала `sudo rm -rf /usr/lib/ollama`.

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
контекст **всего 4096 токенов** на картах меньше 24 ГБ, а сами доки Ollama говорят:
*«coding tools should be set to at least 64000 tokens»*
([context-length.mdx](https://github.com/ollama/ollama/blob/main/docs/context-length.mdx)).

Более того, **Hermes просто откажется стартовать** при контексте меньше 64000 — его доки
называют это «источником путаницы №1». Так что выставляем сразу и забываем.

Цена: контекст ест видеопамять **сверх** веса модели. Учитывай при выборе размера.

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
`48%/52% CPU/GPU` — модель не поместилась в видеопамять или драйвер старый. Вернись к Шагу 0.

Ограничить набор карт (в DGX их несколько):

```bash
nvidia-smi -L                       # взять UUID карт
export CUDA_VISIBLE_DEVICES=GPU-xxxx,GPU-yyyy
```

UUID надёжнее номеров — номера могут переехать между перезагрузками.

---

## Какие модели ставить

### Сначала — честная оговорка

**ollama.com не публикует требования по VRAM.** Только вес файла. Все цифры ниже — это
**вес весов модели**, проверенный прямым запросом к реестру. Реальный расход видеопамяти
выше: `VRAM ≈ вес + KV-кэш + накладные`. При контексте 64k добавляй заметный запас.

Ещё: **все заявления «лучшая модель» — это слова вендоров.** Например, ornith заявляет
SOTA по Terminal-Bench и SWE-Bench на своей же странице. Независимого подтверждения нет.
Так что «топ» ниже — это про соответствие железу и здравый смысл, а не про доказанное первенство.

### Модели, которые НЕ работают локально

Не трать время: у них есть только тег `:cloud`, скачать нельзя. Это `glm-5.1`, `glm-5.2`,
`minimax-m2.5`, `minimax-m2.7`, `minimax-m3`, `kimi-k2.6`, `kimi-k2.7-code`, `deepseek-v4-flash`,
`deepseek-v4-pro`, `nemotron-3-ultra`, `gemini-3-flash-preview`.

### Топ-3 по объёму видеопамяти

**Как пользоваться таблицей — правило одно, без исключений:**

1. Возьми VRAM **одной карты** из `nvidia-smi` (не сумму!). Модель по умолчанию грузится
   в одну карту, так что решает именно эта цифра.
2. Найди свою строку в таблице ниже. Диапазоны **не пересекаются** — подходит ровно одна.
3. Строку «несколько карт» бери **только** если модель из твоей строки уже стоит, а нужна
   ещё крупнее — тогда Ollama размажет её по картам.

| VRAM одной карты | Твой набор | Типичные карты |
|---|---|---|
| менее 24 ГБ | **Набор S** | — |
| 24–47 ГБ | **Набор A** | V100 32GB, A100 40GB |
| 48–79 ГБ | **Набор B** | — |
| 80 ГБ и больше | **Набор C** | A100 80GB, H100, H200 |

#### Набор S — менее 24 ГБ на карту

| Роль | Модель | Вес |
|---|---|---|
| 🥇 Кодинг | `ollama pull ornith:9b` | 5.6 ГБ |
| 🥈 Рассуждения | `ollama pull lfm2.5-thinking:1.2b` | 0.7 ГБ |
| 🥉 Универсал | `ollama pull gemma4:12b` | 7.6 ГБ |

⚠️ **Честно: на такой карте агенты будут работать плохо.** И дело даже не в модели.
При VRAM меньше 24 ГБ Ollama по умолчанию даёт контекст 4k, а мы требуем 64k — контекст
съест память сверх весов. Плюс документация OpenClaw прямо запрещает давать инструменты
слабым моделям. Это конфигурация «попробовать», а не «работать».

#### Набор A — 24–47 ГБ на карту

| Роль | Модель | Вес |
|---|---|---|
| 🥇 Кодинг | `ollama pull qwen3.6:27b` | 17.4 ГБ |
| 🥈 Рассуждения | `ollama pull gpt-oss:20b` | 13.8 ГБ |
| 🥉 Быстрая | `ollama pull gemma4:12b` | 7.6 ГБ |

#### Набор B — 48–79 ГБ на карту

| Роль | Модель | Вес |
|---|---|---|
| 🥇 Кодинг | `ollama pull ornith:35b-q8_0` | 36.9 ГБ |
| 🥈 Рассуждения | `ollama pull gpt-oss:120b` | 65.4 ГБ |
| 🥉 Универсал | `ollama pull qwen3.6:35b-a3b` | 23.9 ГБ |

`gpt-oss:120b` при 65.4 ГБ весов и контексте 64k впритык влезает в 79 ГБ. Не заработает —
бери `nemotron-cascade-2:30b` (24.3 ГБ).

#### Набор C — 80 ГБ и больше на карту

| Роль | Модель | Вес |
|---|---|---|
| 🥇 Кодинг | `ollama pull ornith:35b-q8_0` | 36.9 ГБ |
| 🥈 Рассуждения | `ollama pull gpt-oss:120b` | 65.4 ГБ |
| 🥉 Универсал | `ollama pull qwen3.6:35b-a3b-q8_0` | 38.7 ГБ |

`q8_0` — менее агрессивное сжатие, качество выше. Раз память позволяет, бери его: доки
OpenClaw прямо советуют *«Always run the largest / full-size variant you can host»*.

#### Несколько карт — суммарно 160 ГБ и больше

Только если наборов выше уже мало.

| Роль | Модель | Вес |
|---|---|---|
| 🥇 Кодинг | `ollama pull devstral-2` | 74.9 ГБ |
| 🥈 Рассуждения | `ollama pull nemotron-3-super:120b` | 86.8 ГБ |
| 🥉 Кодинг-MoE | `ollama pull qwen3-coder-next` | 51.7 ГБ |

`nemotron-3-super:120b` в одну 80-гигабайтную карту **не влезет** — нужно минимум две.

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
| **OpenAI-совместимый** | `http://localhost:11434/v1` | Hermes, Ouroboros, NemoClaw |
| Родной Ollama | `http://localhost:11434/api` | сам `ollama` |

Источники: [anthropic-compatibility.mdx](https://github.com/ollama/ollama/blob/main/docs/api/anthropic-compatibility.mdx),
[openai-compatibility.mdx](https://github.com/ollama/ollama/blob/main/docs/api/openai-compatibility.mdx).

По умолчанию Ollama слушает только `127.0.0.1`. Открыть по сети (**только в доверенной
сети** — авторизации там нет):

```bash
Environment="OLLAMA_HOST=0.0.0.0:11434"
```

⚠️ **Отдельная ловушка для OpenClaw:** ему нужен адрес **без** `/v1`. Его доки предупреждают,
что через `/v1` ломается вызов инструментов. Подробности — в [06-openclaw.md](06-openclaw.md).

---

## Готово, если

- [ ] `ollama --version` печатает версию
- [ ] `systemctl status ollama` — `active (running)`
- [ ] `ollama ps` показывает `100% GPU` в колонке `PROCESSOR`
- [ ] `ollama pull` доходит до 100%, а не виснет на 0%
- [ ] `curl http://localhost:11434/api/tags` отдаёт JSON со списком моделей

Дальше: [01-claude-code-local.md](01-claude-code-local.md) — подключить Claude Code
к тому, что ты только что поднял.
