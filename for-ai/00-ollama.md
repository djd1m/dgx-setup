# 00. Ollama — рецепт для AI-кодера

Цель: поднять Ollama как systemd-службу на GPU x86_64 Ubuntu / DGX OS и скачать модели под объём VRAM.

Официальные источники: [ollama.com/download/linux](https://ollama.com/download/linux),
[github.com/ollama/ollama](https://github.com/ollama/ollama).
Актуальная версия на момент написания — **v0.32.0** (11 июля 2026).

---

## Предусловия

Выполнить ДО установки. Требования к GPU: [docs/gpu.mdx](https://github.com/ollama/ollama/blob/main/docs/gpu.mdx).

```bash
nvidia-smi
nvidia-smi -L
```

| Проверка | Ожидаемый результат | Если не так |
|---|---|---|
| `nvidia-smi` отработал | вывод с таблицей GPU | **STOP** — GPU не видны, разбираться до установки |
| `Driver Version:` (верхняя строка) | **550 или новее** | **STOP** — обновить драйвер до установки. Со старее 550 Ollama не увидит GPU и молча уйдёт считать на процессоре: работает, но в десятки раз медленнее |
| Compute capability | **5.0 или выше** | **STOP** — карта не годится |
| `Memory-Usage`, правое число | запомнить цифру → `VRAM_PER_GPU` | — |
| `nvidia-smi -L` | список карт, в DGX обычно 4 или 8 → `GPU_COUNT` | — |

Compute capability для типичных карт в DGX — все проходят с запасом:

| GPU | Compute capability | Годится |
|---|---|---|
| V100 | 7.0 | ✅ |
| A100 | 8.0 | ✅ |
| H100 / H200 | 9.0 | ✅ |

---

## Переменные

Получить/решить до старта.

| Переменная | Как получить | Пример / формат |
|---|---|---|
| `VRAM_PER_GPU` | `nvidia-smi`, колонка `Memory-Usage`, правое число | ГБ на **одну** карту, напр. `80`. **Этой цифрой выбирается набор моделей — не суммой** |
| `GPU_COUNT` | `nvidia-smi -L`, число строк | `4` или `8` |
| `VRAM_TOTAL` | `VRAM_PER_GPU × GPU_COUNT` | ГБ суммарно. Нужна только для строки «несколько карт» (≥160 ГБ) |
| `DRIVER_VERSION` | `nvidia-smi`, верхняя строка `Driver Version:` | должно быть ≥ 550 |
| `PROXY_URL` | взять у человека; нужен только если `ollama pull` виснет на 0% (Шаг 5) | `https://адрес-твоего-прокси` |
| `GPU_UUIDS` | `nvidia-smi -L` — UUID карт (не номера: номера могут переехать между перезагрузками) | `GPU-xxxx,GPU-yyyy` |

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

Нужна установка без интернета:

```bash
curl -fsSL https://ollama.com/download/ollama-linux-amd64.tar.zst \
    | sudo tar x -C /usr
```

Обновление поверх старой версии — сначала:

```bash
sudo rm -rf /usr/lib/ollama
```

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
- По умолчанию Ollama даёт контекст **всего 4096 токенов** на картах меньше 24 ГБ, а доки Ollama говорят: *«coding tools should be set to at least 64000 tokens»* ([context-length.mdx](https://github.com/ollama/ollama/blob/main/docs/context-length.mdx)).
- **Hermes просто откажется стартовать** при контексте меньше 64000 — его доки называют это «источником путаницы №1».
- Цена: контекст ест видеопамять **сверх** веса модели. Учитывать при выборе размера (см. Матрицу).

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

Если не так: `CPU` или смесь вроде `48%/52% CPU/GPU` → модель не поместилась в видеопамять или драйвер старый → вернуться к Предусловиям.

Ограничить набор карт (в DGX их несколько):

```bash
nvidia-smi -L                       # взять UUID карт
export CUDA_VISIBLE_DEVICES=GPU-xxxx,GPU-yyyy
```

UUID надёжнее номеров — номера могут переехать между перезагрузками.

### Шаг 7. Скачать модели по матрице

Определить набор по `VRAM_PER_GPU` (Матрица ниже), выполнить `ollama pull` из выбранного набора.

Ожидаемый результат: каждый pull доходит до 100%.

Если не так: см. Шаг 5.

---

## Матрица выбора модели

### Оговорки (сохранить, не выбрасывать)

- **ollama.com не публикует требования по VRAM.** Только вес файла. Все цифры ниже — **вес весов модели**, проверенный прямым запросом к реестру. Реальный расход видеопамяти выше: `VRAM ≈ вес + KV-кэш + накладные`. При контексте 64k добавлять заметный запас.
- **Все заявления «лучшая модель» — это слова вендоров.** Например, ornith заявляет SOTA по Terminal-Bench и SWE-Bench на своей же странице. Независимого подтверждения нет. «Топ» ниже — про соответствие железу и здравый смысл, а не про доказанное первенство.
- Каждый тег в списках проверен живым запросом к реестру — выдуманных нет.

### Модели, которые НЕ работают локально — не пытаться

Только тег `:cloud`, скачать нельзя: `glm-5.1`, `glm-5.2`, `minimax-m2.5`, `minimax-m2.7`,
`minimax-m3`, `kimi-k2.6`, `kimi-k2.7-code`, `deepseek-v4-flash`, `deepseek-v4-pro`,
`nemotron-3-ultra`, `gemini-3-flash-preview`.

### Выбор набора — правило одно, без исключений

1. Взять VRAM **одной карты** (`VRAM_PER_GPU` из `nvidia-smi`), **не сумму**. Модель по умолчанию грузится в одну карту, так что решает именно эта цифра.
2. Найти строку в таблице. Диапазоны **не пересекаются** — подходит ровно одна.
3. Строку «несколько карт» брать **только** если модель из своей строки уже стоит, а нужна ещё крупнее — тогда Ollama размажет её по картам.

| VRAM одной карты | Набор | Типичные карты |
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
брать `nemotron-cascade-2:30b` (24.3 ГБ).

#### Набор C — 80 ГБ и больше на карту

| Роль | Модель | Вес |
|---|---|---|
| 🥇 Кодинг | `ollama pull ornith:35b-q8_0` | 36.9 ГБ |
| 🥈 Рассуждения | `ollama pull gpt-oss:120b` | 65.4 ГБ |
| 🥉 Универсал | `ollama pull qwen3.6:35b-a3b-q8_0` | 38.7 ГБ |

`q8_0` — менее агрессивное сжатие, качество выше. Раз память позволяет, брать его: доки
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
что через `/v1` ломается вызов инструментов. Подробности — в [06-openclaw.md](../for-human/06-openclaw.md).

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
8. **Не выбирать набор по суммарной VRAM.** Набор определяется VRAM **одной карты**. Строка «несколько карт» — только если модель из своего набора уже стоит, а нужна крупнее.
9. **Модели с тегом `:cloud`** (список выше) — не пытаться скачать, локально не работают.
10. **`OLLAMA_HOST=0.0.0.0:11434`** — не включать самовольно: авторизации нет, только доверенная сеть, решение человека.
11. **Набор S (менее 24 ГБ на карту) — конфигурация «попробовать», а не «работать».** Контекст по умолчанию 4k против требуемых 64k, доки OpenClaw запрещают давать инструменты слабым моделям. Не выдавать такую установку за рабочую — предупредить человека.

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
systemctl show ollama -p Environment | grep -q "HTTP_PROXY=" \
  && { echo "FAIL 7: HTTP_PROXY is set — remove it"; FAIL=1; } || echo "OK 7"

[ "$FAIL" -eq 0 ] && echo "ALL CHECKS PASSED" || echo "CHECKS FAILED"
```

Чек-лист (то же словами):

- [ ] `ollama --version` печатает версию
- [ ] `systemctl status ollama` — `active (running)`
- [ ] `ollama ps` показывает `100% GPU` в колонке `PROCESSOR`
- [ ] `ollama pull` доходит до 100%, а не виснет на 0%
- [ ] `curl http://localhost:11434/api/tags` отдаёт JSON со списком моделей
- [ ] `OLLAMA_CONTEXT_LENGTH=64000` в окружении службы
- [ ] `HTTP_PROXY` не выставлен

Дальше: [01-claude-code-local.md](../for-human/01-claude-code-local.md) — подключить Claude Code
к поднятому движку.
