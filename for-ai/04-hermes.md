# 04. Hermes Agent (Nous Research) — рецепт для ИИ-агента

**Цель:** установить Hermes Agent 0.18.2 ([NousResearch/hermes-agent](https://github.com/NousResearch/hermes-agent), MIT)
на DGX Spark / GB10 (aarch64, DGX OS) без монитора, подключить к локальной Ollama и убедиться, что
вызовы инструментов **выполняются**, а не печатаются текстом.

**Платформа целевая — Tier 1:** *«Linux / WSL2 (x86_64, aarch64)»*.

## 🚨 Прочитай до первой команды

- Пакет `hermes-agent` в **npm — НЕОФИЦИАЛЬНЫЙ**. Мейнтейнер `wyrtensi <wyrtensi@gmail.com>`,
  репозиторий `github.com/wyrtensi/hermes-agent-npm`, самоописание — *«**Unofficial** npm bridge
  for Hermes Agent 0.18.2»*. Nous Research **нигде не документирует** установку через npm.
  **НИКОГДА не выполняй `npm install hermes-agent`.**
- Установка из **PyPI явно неподдерживаемая**: *«Unsupported: installs via `pypi` (e.g.
  `uv tool install hermes-agent`, `pip install hermes-agent`, etc.)»*, и PR с исправлениями
  **приниматься не будут** —
  [platform-support.md](https://raw.githubusercontent.com/NousResearch/hermes-agent/main/website/docs/getting-started/platform-support.md).
  **НИКОГДА не выполняй `pip install hermes-agent` / `uv tool install hermes-agent`.**
- **Единственный поддерживаемый способ — curl-инсталлятор из Шага 2.**
- Hermes — это **Python 3.11 (через `uv`), НЕ Node**. Node.js 22 нужен **только** для
  браузерной автоматизации и моста WhatsApp. Единственное настоящее требование — `git`.

---

## Три способа запуска — реши ДО установки

**Этот рецепт описывает способ №1 (curl-инсталлятор на хост).** Остальные два — контекст, чтобы
ты не перепутал слои.

| Способ | Где живёт **сам Hermes** | Когда брать |
|---|---|---|
| **curl-инсталлятор** (этот рецепт) | **на хосте**, venv в `~/.hermes/` | **по умолчанию** |
| Официальный образ `nousresearch/hermes-agent` | в контейнере, данные в `/opt/data` | свой Docker |
| Через [NemoClaw](03-nemoclaw.md) | **в песочнице OpenShell** | нужна изоляция всего агента |

### 🚨 Две независимые оси — НЕ смешивай

Отдельно от способа запуска у Hermes настраивается **terminal backend**. Он решает, **где
выполняются команды агента**, а НЕ где живёт сам Hermes. Их шесть: `local`, `docker`, `ssh`,
`singularity`, `modal`, `daytona`.

| Ось | Что решает |
|---|---|
| Способ запуска (таблица выше) | где живёт **процесс Hermes** |
| `terminal.backend` | где выполняются **команды агента** |

Оси **независимы**. Hermes может стоять на хосте, а команды гонять в контейнере:

```yaml
terminal:
  backend: docker
```

Дословно: *«the agent runs on your host but executes every command inside a single, persistent
Docker sandbox»* —
[docker.md](https://github.com/NousResearch/hermes-agent/blob/main/website/docs/user-guide/docker.md).

**Рекомендация по умолчанию: установка на хост (Шаг 2) + `terminal.backend: docker`.**
Если задача — «чтобы агент не сломал систему командой», этого хватает, и NemoClaw **не нужен**.
NemoClaw добавляет другое: изоляцию **самого процесса** Hermes и **сетевую политику**.

### Вариант с NemoClaw — только если нужна изоляция всего агента

Hermes там запускается **внутри песочницы OpenShell**. Дословно: *«Create a **sandboxed** Hermes
agent, then chat with it from the dashboard or terminal»* —
[quickstart NemoClaw для Hermes](https://docs.nvidia.com/nemoclaw/user-guide/hermes/get-started/quickstart.md).

Ключевое отличие от [инструкции 03](03-nemoclaw.md) — переменная `NEMOCLAW_AGENT`:

```bash
curl -fsSL https://www.nvidia.com/nemoclaw.sh | \
  NEMOCLAW_INSTALL_TAG=v0.0.84 \
  NEMOCLAW_AGENT=hermes \
  NEMOCLAW_PROVIDER=ollama \
  NEMOCLAW_ACCEPT_THIRD_PARTY_SOFTWARE=1 \
  NEMOCLAW_SANDBOX_NAME=my-hermes \
  bash
```

**Провайдер обязан быть `ollama`.** Управление — через `nemohermes`, это *«the NemoClaw CLI with
Hermes pre-selected»*:

```bash
nemohermes my-hermes status
nemohermes my-hermes logs --follow
nemohermes my-hermes rebuild
```

⚠️ **Взвесь зрелость слоёв, прежде чем предлагать это человеку.** Hermes — **0.18.2**, MIT,
платформа Tier 1. NemoClaw — **alpha 0.1.0**, авторы сами пишут *«interfaces can change between
releases»*, установщик **не пинится по хэшу** (сравни с Шагом 1 этого рецепта), а у изоляции есть
[известная оговорка](03-nemoclaw.md) (issue #3280). Ты добавляешь незрелый слой ради изоляции.
Если не уверен — **бери Hermes сам по себе с `backend: docker`**.

### Telegram в песочнице NemoClaw — проверено, работает через пресет

Политика OpenShell — **deny-by-default**, поэтому без пресета исходящий трафик до
`api.telegram.org` не пройдёт. Пресет существует и официален:
[`src/lib/messaging/channels/telegram/policy/hermes.yaml`](https://github.com/NVIDIA/NemoClaw/blob/main/src/lib/messaging/channels/telegram/policy/hermes.yaml)
разрешает `host: api.telegram.org`, `port: 443`, маршруты `GET /bot*/**`, `POST /bot*/**`,
`GET /file/bot*/**` — и только для бинарей `/usr/local/bin/node`, `/usr/bin/python3*`,
`/opt/hermes/.venv/bin/python`.

**По умолчанию он не активен.** В
[`nemoclaw-blueprint/policies/tiers.yaml`](https://github.com/NVIDIA/NemoClaw/blob/main/nemoclaw-blueprint/policies/tiers.yaml)
Telegram есть **только в тире `open`**; в `restricted` и `balanced` (дефолт) его нет.

**Диагностическое правило:** бот в песочнице не отвечает → **сначала проверить пресет/тир**,
и только потом идти в раздел про DNS-блокировку ниже. Симптомы неотличимы, а причины
разные, и лечение от одной не помогает от другой.

---

## Предусловия

1. Инструкция [00-ollama.md](00-ollama.md) выполнена.
2. В `ollama.service` стоит строка:
   ```ini
   Environment="OLLAMA_CONTEXT_LENGTH=64000"
   ```
3. Проверить контекст **до установки** — колонка `CONTEXT`:
   ```bash
   ollama ps
   ```
   **Ожидаемый результат:** модель загружена, в колонке `CONTEXT` значение **не меньше 64000**.

   **Если не так, то:** останови рецепт и вернись в 00-ollama.md. Hermes требует контекст
   не меньше **64000** токенов и **отвергает меньший прямо на старте**; Ollama по умолчанию
   даёт **4096** при небольшом объёме памяти. Через OpenAI-совместимый API это **не чинится** —
   только на стороне сервера Ollama. Разовый обход:
   ```bash
   OLLAMA_CONTEXT_LENGTH=64000 ollama serve
   ```
   Если `ollama ps` пуст — модель не загружена; загрузи её и повтори проверку.

4. Наличие базовых утилит:
   ```bash
   command -v git curl xz
   ```
   **Ожидаемый результат:** три пути. `curl` и `xz-utils` нужны, т.к. Node качается архивом `.tar.xz`.

   **Если не так, то:** доустанови недостающее через `apt-get install -y git curl xz-utils`.

> Помни: контекст 64k занимает память **сверх** веса модели. На DGX Spark с ~119 ГБ единой памяти это не ограничение.

---

## Переменные

| Переменная | Значение по умолчанию | Примечание |
|---|---|---|
| `HERMES_MODEL` | `qwen3-coder:30b` | **обязано совпадать с выводом `ollama list`** |
| `HERMES_BASE_URL` | `http://localhost:11434/v1` | Ollama, **с `/v1`** |
| `HERMES_CONTEXT_LENGTH` | `64000` | минимум, ниже Hermes не стартует |
| `HERMES_PROVIDER` | `custom` | |
| `HERMES_CONFIG` | `~/.hermes/config.yaml` | точный путь берётся из `hermes config path` |
| `HERMES_ENV` | `~/.hermes/.env` | точный путь берётся из `hermes config env-path` |
| `EXPECTED_SHA256` | `c2e4326c1660bd45f64321996eb15bda35e7a4649e32a310495a61972a2804c8` | 3133 строки; **изменится с новыми версиями** |

```bash
export HERMES_MODEL="qwen3-coder:30b"
export HERMES_BASE_URL="http://localhost:11434/v1"
export HERMES_CONTEXT_LENGTH=64000
export HERMES_PROVIDER="custom"
```

Куда всё ставится:

| Режим | Код | Бинарник | Данные |
|---|---|---|---|
| Обычный | `~/.hermes/hermes-agent/` | `~/.local/bin/hermes` | `~/.hermes/` |
| От root | `/usr/local/lib/hermes-agent/` | `/usr/local/bin/hermes` | `/root/.hermes/` |

**sudo для основной установки не нужен.** Python приходит через `uv` без прав root. sudo нужен
только для системных пакетов, и скрипт корректно переживает его отсутствие — просто напечатает
команду для администратора.

---

## Шаги

### Шаг 1. Проверка цепочки поставки — ОБЯЗАТЕЛЬНО ДО УСТАНОВКИ

Скрипт по адресу инсталлятора должен **побайтово совпадать** с исходником в репозитории.

```bash
curl -fsSL https://hermes-agent.nousresearch.com/install.sh | sha256sum
curl -fsSL https://raw.githubusercontent.com/NousResearch/hermes-agent/main/scripts/install.sh | sha256sum
```

**Ожидаемый результат:** обе команды печатают **одинаковую** сумму.

На момент написания:
```
SHA256: c2e4326c1660bd45f64321996eb15bda35e7a4649e32a310495a61972a2804c8
Строк:  3133
```

> Закреплённое значение **изменится с новыми версиями** — это нормально и **не является**
> поводом для остановки. Критерий один: **две команды дают одинаковый результат**.

Машинная проверка:

```bash
A=$(curl -fsSL https://hermes-agent.nousresearch.com/install.sh | sha256sum | awk '{print $1}')
B=$(curl -fsSL https://raw.githubusercontent.com/NousResearch/hermes-agent/main/scripts/install.sh | sha256sum | awk '{print $1}')
echo "served=$A"; echo "repo=$B"
[ -n "$A" ] && [ "$A" = "$B" ] && echo "SUPPLY_CHAIN_OK" || echo "SUPPLY_CHAIN_MISMATCH"
```

**Если суммы РАЗЛИЧАЮТСЯ (`SUPPLY_CHAIN_MISMATCH`), то: ОСТАНОВИСЬ. НЕ УСТАНАВЛИВАЙ.**
Не пытайся обойти, не ставь из npm/PyPI, не качай «другую» ссылку. Сообщи пользователю
обе суммы и жди решения человека.

**Если хоть одна сумма пустая, то:** адрес недоступен — см. Стоп-условия (сетевая доступность).

### Шаг 2. Установка (headless DGX)

```bash
curl -fsSL https://hermes-agent.nousresearch.com/install.sh | bash -s -- --skip-browser
```

**`--skip-browser` на DGX без монитора обязателен.** Он пропускает скачивание Chromium и
Playwright — а заодно единственный шаг, которому реально нужен root. Дословно из документации:
*«The only thing on the install path that genuinely needs root is Playwright's `--with-deps` step»*.

Остальные документированные флаги: `--skip-setup`, `--no-venv`, `--branch NAME`, `--commit SHA`,
`--dir PATH`, `--hermes-home PATH`, `--non-interactive`.

**Ожидаемый результат:** установка завершается без ошибок; появляется `~/.local/bin/hermes`.

**Если не так, то:**
- Предупреждения о недоступности `pypi.org` и `duckduckgo.com` — это **предупреждения, а не
  ошибки**: установщик продолжит, сообщив, что веб-поиск и часть зависимостей могут не работать.
  Не останавливайся из-за них.
- Установщик качает с `github.com`, `astral.sh` (uv), `nodejs.org`, npm, Chromium (отключён
  флагом). Из России эти адреса могут быть недоступны — тот же случай, что и с `ollama pull`.
- Если скрипт просит системные пакеты и нет sudo — он напечатает команду для администратора;
  выполни её при наличии прав и повтори.

### Шаг 3. Активация PATH

```bash
source ~/.bashrc
command -v hermes && hermes --version
```

**Ожидаемый результат:** путь к бинарнику и напечатанная версия.

**Если не так, то:** проверь наличие `~/.local/bin/hermes` (обычный режим) или
`/usr/local/bin/hermes` (установка от root) и что соответствующий каталог есть в `$PATH`.

### Шаг 4. Подключение к Ollama

Два документированных способа. **Третьего не изобретай.**

**Способ A — мастер (интерактивный):**

```bash
hermes model
```

Выбери **«Custom endpoint (self-hosted / VLLM / etc.)»**, укажи `http://localhost:11434/v1`,
ключ пропусти, введи имя модели.

> ⚠️ `hermes model` **нельзя запускать внутри чата**. Только отдельной командой. Команда
> `/model` внутри сессии умеет лишь переключаться между уже настроенными провайдерами.

**Способ B — прямая правка `~/.hermes/config.yaml` (предпочтителен для автономного агента):**

```bash
hermes config path   # узнать точный путь
```

Привести `model`-секцию к виду:

```yaml
model:
  default: qwen3-coder:30b
  provider: custom
  base_url: http://localhost:11434/v1
  context_length: 64000
```

**Имя модели должно совпадать с выводом `ollama list`.** Сверь перед правкой:

```bash
ollama list
```

> ✅ **ПРОВЕРЕНО вживую** (образ `v2026.7.7.2`, 2026-07-19): **`hermes config set` принимает
> точечные ключи и пишет прямо в `config.yaml`.** Работают `model.default`, `model.provider`,
> `model.base_url`, `model.context_length` — каждый отвечает `✓ Set <key> = <value> in
> /opt/data/config.yaml`. Это **неинтерактивный** путь, и он предпочтителен для автономного
> агента и особенно для нескольких контейнеров: **`hermes model` — только мастер**, флагов
> провайдера/модели/URL у него нет (его опции — про OAuth-вход в Nous Portal).
>
> Оговорка: в официальной документации этот сеттер по-прежнему не описан — поведение
> подтверждено **эмпирически на этой версии** и может измениться в будущих. Если `config set`
> отвалится — откат на `hermes model` или прямую правку yaml.

### Способ C — неинтерактивно (кастомный OpenAI-совместимый endpoint)

```bash
hermes config set model.default        <имя-модели-как-в-/v1/models>
hermes config set model.provider       openai-api
hermes config set model.base_url       https://<хост>/v1
hermes config set model.context_length 64000        # ниже Hermes не стартует
```

Ключ, если endpoint требует авторизации, — `OPENAI_API_KEY` в `.env` (не в `config.yaml`).
**Имя модели должно совпадать буква-в-букву** с тем, что endpoint отдаёт в `/v1/models`;
сверить живой список — `hermes model --refresh`.

Для нескольких контейнеров — цикл:

```bash
for s in hermes-me hermes-wife hermes-son; do
  docker compose exec -T "$s" hermes config set model.base_url https://<хост>/v1
done
docker compose restart
```

**Ожидаемый результат:**

```bash
hermes config show
```
показывает `base_url: http://localhost:11434/v1`.

**Если не так, то:** проверь, что правил файл из `hermes config path`, а не другой; убедись,
что `base_url` **с `/v1`** — без него не заработает.

### Шаг 5. Диагностика

```bash
hermes doctor
```

**Ожидаемый результат:** без жалоб.

**Если не так, то:** читай конкретную жалобу. Частые причины — контекст < 64000 (см.
Предусловия), несовпадение имени модели с `ollama list`, отсутствующий `/v1` в `base_url`.

### Шаг 6. Таймаут (только если модель отвечает медленно и всё падает по таймауту)

В `~/.hermes/.env` (путь — из `hermes config env-path`):

```
HERMES_API_TIMEOUT=1800
```

**Это только переменная окружения — в `config.yaml` такого ключа нет.** Не добавляй его в yaml.

### Шаг 7. vLLM вместо Ollama — на DGX Spark НЕ предлагать

Документация Hermes описывает vLLM подробнее Ollama, и это создаёт ложный сигнал.
**На DGX Spark vLLM не ставить.** Полный разбор — [08-vllm-vs-ollama.md](08-vllm-vs-ollama.md).
Коротко:

- **Быстрее не будет:** при одном пользователе оба движка упираются в шину 273 ГБ/с.
- **[#46307](https://github.com/vllm-project/vllm/issues/46307)** (open, на GB10) вешает
  хост: *«SSH dies; the machine requires a hard power-cycle»*. По SSH это не чинится.
- [Playbook NVIDIA для кодинг-агентов на DGX Spark](https://github.com/NVIDIA/dgx-spark-playbooks/blob/main/nvidia/cli-coding-agent/README.md)
  построен на Ollama.

🛑 **`--tensor-parallel-size` на этой машине неприменим** — GB10 единый чип, GPU один.
Встретил этот флаг в примере из интернета — это признак, что пример писался под другое железо.

**Если человек всё-таки настаивает** (прочитав 08) или речь о другой машине:

```bash
vllm serve <модель> --port 8000 --max-model-len 65536 \
  --enable-auto-tool-choice --tool-call-parser hermes
```

> ⚠️ **`--enable-auto-tool-choice` и `--tool-call-parser hermes` ОБЯЗАТЕЛЬНЫ.** Без них,
> дословно: *«tool calls won't work — the model will output tool calls as text»* — агент будет
> **печатать вызовы инструментов текстом вместо их выполнения**. Парсер `hermes` подходит
> для Qwen 2.5 и Hermes 2/3.

Дальше `base_url: http://localhost:8000/v1`.

**По умолчанию: Ollama.** Скорость на этой машине определяется выбором MoE-модели
([00-ollama.md](00-ollama.md)), а не движком — разница десятикратная.

---

## Файлы конфигурации

| Файл | Что внутри |
|---|---|
| `~/.hermes/config.yaml` | модель, провайдер, base_url |
| `~/.hermes/.env` | ключи и секреты |
| `~/.hermes/auth.json` | OAuth-учётки |
| `~/.hermes/` | данные. Меняется через `$HERMES_HOME` |

```bash
hermes config path
hermes config env-path
hermes doctor
```

---

## Шаг 8. Telegram (только если человек попросил)

Не выполняй этот шаг по своей инициативе. Он открывает наружу доступ к агенту с shell.

### 8.1. Данные, которые может дать ТОЛЬКО человек

| Что | Откуда | Можно ли добыть самому |
|---|---|---|
| Токен бота | @BotFather → `/newbot` | **НЕТ** |
| Числовой user ID | @userinfobot | **НЕТ** |

Оба значения запрашивай у человека. **Не выдумывай, не подставляй примеры из документации.**

### 8.2. Конфигурация

Команда:
```bash
hermes gateway setup
```
Ожидаемый результат: интерактивный мастер, выбор Telegram, запрос токена и ID.

Если не подходит интерактивный путь — в `~/.hermes/.env`:

```bash
TELEGRAM_BOT_TOKEN=<токен от человека>
TELEGRAM_ALLOWED_USERS=<числовой ID от человека>
```

Несколько ID — через запятую.

**Если не так:** без `TELEGRAM_ALLOWED_USERS` шлюз откажет **всем** — дословно:
*«Without it, the gateway denies all users by default as a safety measure»*. Это защита,
а не поломка. Не обходи её.

### 8.3. Запуск

```bash
hermes gateway
hermes gateway status
```

Ожидаемый результат: `status` показывает работающий шлюз, бот отвечает человеку в Telegram.

| Команда | Действие |
|---|---|
| `hermes gateway` | запустить |
| `hermes gateway status` | проверить |
| `hermes gateway stop` | остановить |
| `hermes gateway restart` | перезапустить |

### 8.3-bis. Домашний канал («No home channel is set») — НЕ ошибка

При первом контакте бот выводит предложение задать домашний канал. Это **не ошибка и не
стоп-условие** — не чинить, не эскалировать.

- **Что это:** чат, куда Hermes шлёт то, что инициирует сам — результаты **cron-задач** и
  **межплатформенные** сообщения.
- **Как задаётся:** человек набирает `/sethome` **в том самом чате**, который делает домашним.
  Заранее в `config.yaml` не прописывается: chat-id заранее неизвестен (проверено по исходнику
  в образе — `tui_gateway/server.py` советует *«`/sethome` on the destination chat first»*).
- **Env-переменные `<PLATFORM>_HOME_CHANNEL` — не общий механизм.** В коде явные исключения
  только для email (`EMAIL_HOME_ADDRESS`) и Weixin. **Для Telegram не использовать.**
- Если cron и агент-инициированные сообщения не нужны — можно игнорировать.
- Несколько инстансов → каждый человек делает `/sethome` сам, в своём чате.

🛑 **Не путать с `terminal.home_mode`** в `config.yaml` — это домашний каталог для выполнения
команд агента. К домашнему чату отношения не имеет; правкой этого ключа сообщение не убирается.

### 8.4. ✅ Если Telegram недоступен — сначала ОДНА строка

Симптом: Hermes сообщает, что не видит эндпоинт Telegram, и просит SOCKS5.

**Не поднимай прокси.** Сначала:

```bash
echo 'TELEGRAM_FALLBACK_IPS=149.154.167.220' >> ~/.hermes/.env
hermes gateway restart
```

Ожидаемый результат: шлюз стартует, бот отвечает.

**Проверено на живой установке в России, июль 2026: помогло, прокси не понадобился.**
*(Одна машина, один провайдер, один момент. Обобщается порядок действий, а не результат.)*

Причина: по имени `api.telegram.org` не резолвится, по сырому IP — работает. Провайдер
режет **DNS**, а не адрес. Лечение — не ходить в DNS.

**Если не так (не помогло):** переходи к 8.5.

### 8.5. SOCKS5 — только если 8.4 не сработал

```bash
TELEGRAM_PROXY=socks5://127.0.0.1:10808
```

Работают и `HTTPS_PROXY` / `HTTP_PROXY` / `ALL_PROXY`.

**ДО настройки Hermes проверь прокси независимо:**

```bash
curl -s --socks5 127.0.0.1:10808 https://api.ipify.org; echo
```

Ожидаемый результат: IP сервера человека, а не домашний IP.
**Если не так:** прокси не работает — чини прокси, а не Hermes.

### 8.6. Грабли

**Docker-бэкенд + вложения.** При `terminal.backend: docker` вложения уходят **с хоста**,
а не из контейнера. Файл, созданный агентом внутри, наружу не отправится:

```yaml
terminal:
  backend: docker
  docker_volumes:
    - "/home/user/.hermes/cache/documents:/output"
```

**Бот молчит в группе.** Privacy Mode. Выключается у BotFather (`/mybots` → Bot Settings →
Group Privacy → Turn off). Одного этого мало — дословно: *«You must remove and re-add the
bot to any group after changing the privacy setting»*.

### 8.7. Ограничение прав (рекомендуется)

```yaml
gateway:
  platforms:
    telegram:
      extra:
        allow_from:
          - "<ID>"
        allow_admin_from:
          - "<ID>"
        user_allowed_commands:
          - status
          - model
```

Проверка уровня доступа человеком — команда `/whoami` в чате.

---

## Шаг 8-bis. Несколько инстансов (профили) — рецепт + когда это оправдано

Выполняй **только если человек попросил несколько ботов/агентов**. Не плоди инстансы по своей
инициативе — сначала проверь по таблице целесообразности ниже, не решается ли задача одним.

Механизм — **профили**: каждый профиль это отдельный агент со своим `HERMES_HOME`
(`~/.hermes/profiles/<имя>/`), а значит своим `config.yaml`, `.env`, токеном, памятью,
персоной, скиллами, процессом и systemd-юнитом. Код общий. Источники:
[profiles.md](https://github.com/NousResearch/hermes-agent/blob/main/website/docs/user-guide/profiles.md),
[multi-profile-gateways.md](https://github.com/NousResearch/hermes-agent/blob/main/website/docs/user-guide/multi-profile-gateways.md).

### Рецепт на N-й инстанс

```bash
hermes profile create <имя>            # создаёт ~/.hermes/profiles/<имя>/
hermes -p <имя> gateway setup          # свой .env: TELEGRAM_BOT_TOKEN + TELEGRAM_ALLOWED_USERS
hermes -p <имя> gateway install        # свой сервис hermes-gateway-<имя>.service
hermes -p <имя> gateway start
```

`hermes -p <имя> …` = обращение к профилю; после `create` работает и алиас-команда `<имя> …`.

**Инварианты (соблюдать):**
- **Свой токен на каждый профиль.** Одинаковый токен на два профиля Hermes отвергает на старте
  («same-token conflict»). Токен даёт только человек (@BotFather), в git/логи/чат не писать —
  как в Стоп-условиях Шага 8.
- **Свой `TELEGRAM_ALLOWED_USERS`** в `.env` каждого профиля (fail-closed на каждом).
- **Порт разводить не нужно:** Telegram = long polling (`getUpdates`), inbound-порт не
  занимается. Порт всплывает только в webhook-режиме (по умолчанию выключен) → там каждому
  свой `TELEGRAM_WEBHOOK_PORT`.
- **РФ:** `TELEGRAM_FALLBACK_IPS=149.154.167.220` (Шаг 8.4) прописывать в `.env` **каждого**
  профиля — файлы не общие.

### Контейнер — нужен или нет (решает НЕ количество ботов, а чей ввод)

| Случай | Контейнер | Почему |
|---|---|---|
| Несколько ботов **одного** человека | **не нужен** | профили на хосте изолируют конфиг/токены; штатная схема |
| Боты **разных** людей на одном сервере | **обязателен** | см. ниже |

Причина для мультитенанта — радиус поражения shell:

| Схема | Изолировано | Чужой/захваченный бот может |
|---|---|---|
| хост + `backend: local` (дефолт) | ничего | shell как хостовый юзер → вся машина + `~/.hermes/profiles/*` чужих ботов (их токены/`.env`) |
| хост + `backend: docker` | только shell-команды | процесс Hermes на хосте: code-exec, MCP, плагины, хуки, скиллы — **мимо** песочницы |
| контейнер-на-бота (офиц. образ) / OpenShell | весь процесс агента | ограничен своим контейнером — **поддерживаемая** схема для чужого ввода |

Предписание проекта ([SECURITY.md](https://github.com/NousResearch/hermes-agent/blob/main/SECURITY.md)
§2.2, §2.6.4, [security.md](https://github.com/NousResearch/hermes-agent/blob/main/website/docs/user-guide/security.md)):
для чужого/недоверенного ввода — отдельный инстанс + свой allowlist + **whole-process wrapping**
(официальный образ `nousresearch/hermes-agent` по контейнеру на бота, либо NVIDIA OpenShell).
**Не** хостовый `local` и **не** только `docker`-бэкенд.

> **NOT VERIFIED:** multi-container compose в репо не поставляется — схема «контейнер на бота»
> собирается из контракта `HERMES_HOME`/volume (свой хостовый каталог на `/opt/data`, свой токен
> на контейнер; при `network_mode: host` развести порты дашборда/API). Пошаговый рецепт
> «отдельный OS-пользователь на бота» в доках не описан (принцип есть, механики нет).
> Точная строка, где `profile create` прокидывает `HERMES_HOME` в дочерний процесс, — выведена
> из доков и `--profile`-обвязки, построчно до exec не прослежена.

🛑 **Две грабли применения изменений (проверено на живом стенде 2026-07-19) — соблюдать строго:**

| Что менял | Чем применять |
|---|---|
| `secrets/*.env` (токены, ключи, URL) | `docker compose up -d --force-recreate` — **обязательно** |
| `config.yaml` (`model.*`) | `docker compose restart` — достаточно |

1. **`docker compose restart` НЕ перечитывает `env_file`** — переменные впекаются при СОЗДАНИИ
   контейнера. Симптом: `.env` заполнен, а контейнер видит старое → «token … was rejected».
   Диагностика без печати секрета:
   `docker compose exec -T <svc> sh -c 'case "$TELEGRAM_BOT_TOKEN" in REPLACE_ME*) echo ПЛЕЙСХОЛДЕР;; "") echo пусто;; *) echo задан;; esac'`
2. **`base_url` берётся из `config.yaml`, а не из `.env`.** Если `model.base_url` там уже задан —
   используется он; одного `OPENAI_BASE_URL` в `.env` НЕ достаточно. Перенос без утечки URL:
   `docker compose exec -T <svc> sh -c 'hermes config set model.base_url "$OPENAI_BASE_URL"'`

Готовый скелет для случая «разные люди на одном VPS» (3 сервиса, том + токен + allowlist на
каждого, bridge-сеть, backend `local` внутри контейнера):
[`scripts/docker-compose.hermes-multi.example.yml`](../scripts/docker-compose.hermes-multi.example.yml).
Сверено с живым образом и **прогнано вживую 2026-07-19** (Docker 29.1.3, x86_64): команда
`["gateway","run"]`, тег `v2026.7.7.2`, entrypoint `/init` не трогать, host-права через
`HERMES_UID/GID` (не `--user`), bridge-сеть. Проверено: три контейнера бут под s6 без конфликтов,
remap uid + chown тома, токен из `env_file` доходит до Telegram-адаптера (с заглушкой — ожидаемый
reject). С реальными данными осталось: настоящий токен + бэкенд модели (`hermes model`). Детали и
лог-подтверждения — в шапке файла.

### Целесообразность для ОДНОГО человека

Один инстанс уже умеет (не плодить ради этого): много каналов сразу (один шлюз держит
Telegram+Discord+Slack), `/model` в сессии + модель у суб-агента, конкурентные сессии по чату
(дефолт без лимита), `/background` и `delegate_task` для параллельных задач.

Отдельный инстанс нужен, только когда **одновременно** различается «одно-на-инстанс»:

| Сценарий | Отдельный инстанс | Причина |
|---|---|---|
| Своя постоянная память+персона | **Да** | `MEMORY/USER/SOUL.md` по одной на инстанс; `/personality` — оверлей сессии, не память |
| Разный `terminal.backend` одновременно | **Да** | одно значение на инстанс; суб-агенты наследуют бэкенд |
| Настоящий lockdown прав | **Да** | admin/user гейтит лишь слэш-команды; чат несёт доступ к терминалу |
| Крэш-изоляция | **Да** | «процесс на профиль» = независимые домены отказа |
| Отдельная личность бота на аудиторию | **Да** | токен по одному на платформу/профиль |
| Ещё один канал / модель / параллельность | Нет | покрыто одним инстансом (см. выше) |

Цена multi: N процессов+юнитов, N токенов ротировать, память **не** общая между профилями.
Если нужна только изоляция состояния, но не крэш-домены — `multiplex_profiles` (один процесс на
все профили, изоляция конфига/памяти/токенов сохраняется).

> **NOT VERIFIED:** RAM/CPU на один gateway-процесс в доках не указаны → сколько ботов влезет
> на скромный VPS. Возможен ли внутри одного инстанса реально read-only канал (снять `terminal`
> с одной платформы, оставив на другой) — в доках примера нет; классифицировано как «нужен
> отдельный инстанс».

---

## Шаг 8-ter. OpenAI-подписка vs API-ключ в Hermes

Выполняй, только если человек хочет **OpenAI-модели** (а не локальную Ollama). Два разных пути,
**не путать**. Аналогия, которую человек может держать в голове: подписку **Claude Max** в чужом
харнессе использовать нельзя — и по ToS, и технически заблокирована. **У OpenAI мягче**, но с
оговорками ниже. (Верифицировано deep-research 2026-07-19: 24 из 25 утверждений подтверждены
голосованием 3 голосами, 1 опровергнуто.)

### Путь A — подписка (ChatGPT Plus/Pro / Codex Pro, без ключа): провайдер `openai-codex`

Hermes поддерживает **нативно** (в отличие от Claude Max):
- в конфиге `provider: "codex"`; логин — **ChatGPT OAuth device-code** (открыть URL, ввести код),
  **без API-ключа**; команда `hermes model` → выбрать «OpenAI Codex»;
- креды в `~/.hermes/auth.json`; **умеет импортировать `~/.codex/auth.json`** (то, что кладёт Codex CLI).

Ограничения (технические, жёсткие):
- **только Codex-модели**; токен прибит к бэкенду Codex (`chatgpt.com/backend-api/codex/responses`,
  заголовок `originator: codex_cli_rs`), **не** к `api.openai.com`;
- `OPENAI_BASE_URL` для этого провайдера **не действует** (только для `openai-api`) — перенаправить
  на произвольный OpenAI-совместимый endpoint нельзя. Это тот же класс ограничения, что у Anthropic.

🛑 **Стоп-условия / что обязательно сказать человеку (не решать за него):**
- **Серая зона ToS (NOT VERIFIED).** OpenAI документирует подписочный вход только для своих
  поверхностей (ChatGPT desktop, Codex CLI, IDE-расширение — «for local work»); сторонние харнессы
  не упомянуты; для программных/CI-сценариев OpenAI **прямо направляет на API-ключ**. Явного «да»
  нет, явного «нет» тоже; мейнтейнер на прямой вопрос уклонился.
- **Держится на отсутствии enforcement, не на разрешении.** В отличие от Anthropic (заблокировала
  янв/апр 2026) и Google Gemini CLI, OpenAI на середину 2026 технически **не** блокировал сторонний
  Codex-OAuth — но может в любой момент. Гипотеза «запрещён шаринг креденшелов» голосованием
  **опровергнута** — на неё не опираться.
- **Аккаунт-риск.** Авторы OAuth-мостов сами пишут: personal-only, не для коммерции/мультиюзера;
  аккаунт могут флагнуть за необычные паттерны. **Если аккаунт чужой (например, родителя) — прямо
  предупредить.**
- **Гео** — прямого пункта в политиках нет (NOT VERIFIED), но осторожность разумна.

### Путь B — API-ключ (оплата по токенам): провайдер `openai-api` — санкционированный

- `OPENAI_API_KEY` в `~/.hermes/.env`; выбор `provider: openai-api` в `config.yaml` или флаг
  `--provider openai-api`; опционально `OPENAI_BASE_URL` (тогда Hermes игнорирует именованный
  провайдер и бьёт прямо в endpoint, аутентифицируясь `OPENAI_API_KEY`).
- Явно разрешено и предсказуемо. **Ключ — секрет:** только в `.env`, не в git/логи/чат (те же
  правила, что для токена бота, Шаг 8).

### Codex как MCP-сервер — NOT VERIFIED как путь для Hermes

`codex mcp-server` (в CLI ≥ 0.144.6) технически поднимает Codex как MCP по stdio. Но для Hermes это
**избыточно** (есть родной `codex`-провайдер), под капотом та же подписочная OAuth и те же ToS-рамки,
и как рабочий мост именно для Hermes в проверенных источниках он **не подтверждён**. Не предлагать
как решение без отдельной проверки.

**Источники:**
[providers.md](https://github.com/NousResearch/hermes-agent/blob/main/website/docs/integrations/providers.md),
[configuration.md](https://github.com/NousResearch/hermes-agent/blob/main/website/docs/user-guide/configuration.md),
Hermes issue #9283;
[developers.openai.com/codex/auth](https://developers.openai.com/codex/auth),
[learn.chatgpt.com/docs/auth](https://learn.chatgpt.com/docs/auth.md),
[openai/codex discussions/8338](https://github.com/openai/codex/discussions/8338).

---

## Веб-поиск: провайдер и ключи (задаётся целиком через `.env`)

Отдельного мастера не требуется. Проверено по исходнику образа `v2026.7.7.2`
(`tools/web_tools.py`, `agent/web_search_registry.py`, `agent/web_search_provider.py`).

**Автовыбор:** если `web.search_backend` явно не задан, берётся **первый** бэкенд, для которого
есть переменная, в этом порядке:

| # | Бэкенд | Переменная |
|---|---|---|
| 1 | `tavily` | `TAVILY_API_KEY` |
| 2 | `exa` | `EXA_API_KEY` |
| 3 | `parallel` | `PARALLEL_API_KEY` |
| 4 | `firecrawl` | `FIRECRAWL_API_KEY` или `FIRECRAWL_API_URL` |
| 5 | `searxng` | `SEARXNG_URL` (свой инстанс, ключ не нужен) |
| 6 | `brave-free` | `BRAVE_SEARCH_API_KEY` |
| 7 | `ddgs` | — (если пакет `ddgs` импортируется) |

Одного ключа достаточно. **Явная фиксация** (побеждает автовыбор):

```bash
hermes config set web.search_backend tavily
```

Читается `web.search_backend` (предпочтительно), либо `web.backend` (общий с extract).

🛑 **Стоп-условия / грабли:**

1. **У Brave переменная `BRAVE_SEARCH_API_KEY`, НЕ `BRAVE_API_KEY`.** В коде есть обе (короткая —
   для другого), поиск читает длинную. **Не подставлять короткую** — подхвата не будет, и молча.
2. **Платные бэкенды намеренно выше бесплатных.** В коде объяснено: явные пользовательские ключи
   не должен перебивать Nous-OAuth-токен, чья подписка может не давать веб-поиск — иначе отказ
   в рантайме **без отката** на другой бэкенд.
3. **Ключи читаются и из config-слоя Hermes, и из process-env** (`_env_value` → `get_env_value`,
   issue #34290). В контейнере — через `env_file`; **менял `.env` → `up -d --force-recreate`**,
   `restart` не перечитает (см. грабли выше).
4. `SEARXNG_URL` — единственный вариант без внешнего ключа и без внешнего провайдера.
   Предлагать первым, если человек спрашивает про приватность поиска.

---

### Шаг 9. (Опционально) Mem0 OSS — локальная память без облака

Ставить **только если человек просил** базу знаний. Для обычной работы Hermes не требуется.

**Зачем.** Встроенная память Hermes — профиль, а не корпус: `MEMORY.md` ~2200 символов,
`USER.md` ~1375, при переполнении инструмент возвращает **ошибку**. Встроенного RAG нет.
Внешние memory-провайдеры почти все облачные и требуют ключ — **кроме Mem0 в режиме OSS**.

Дословно из [документации интеграции Mem0 с Hermes](https://docs.mem0.ai/integrations/hermes):

> No data is sent to Mem0 Cloud, and no Mem0 API key is required

**Команда:**

```bash
hermes memory setup mem0 --mode oss \
  --oss-llm ollama \
  --oss-embedder ollama \
  --oss-vector qdrant
```

Ожидаемый результат: создан `~/.hermes/mem0.json`, векторное хранилище — локальный Qdrant
в `~/.hermes/mem0_qdrant`.
Если не так: **не править конфиг наугад**, см. оговорку ниже.

**Дословный пример структуры из документации** (он там **с OpenAI** — привожу как есть,
не выдавая за Ollama-вариант):

```json
{
  "mode": "oss",
  "oss": {
    "llm": {"provider": "openai", "config": {"model": "gpt-5-mini"}},
    "embedder": {"provider": "openai", "config": {"model": "text-embedding-3-small"}},
    "vector_store": {"provider": "qdrant", "config": {"path": "~/.hermes/mem0_qdrant"}}
  }
}
```

Имена провайдеров и ключи для Ollama — из
[документации LLM](https://docs.mem0.ai/components/llms/models/ollama)
(`provider: "ollama"`, ключи `model`, `temperature`, `max_tokens`, `ollama_base_url`) и
[документации эмбеддера](https://docs.mem0.ai/components/embedders/models/ollama)
(`provider: "ollama"`, ключи `model`, `embedding_dims`, `ollama_base_url`).

> **NOT VERIFIED:** готового JSON для связки Hermes + Ollama в документации **нет** —
> дословный пример только с OpenAI. Собирать конфиг из документированных имён можно,
> но **предпочтительно `hermes memory setup mem0`**, а не ручная правка. Не выдумывать
> ключи, которых нет в двух страницах выше.

**Обязательно — скачать модель эмбеддингов отдельно:**

```bash
ollama pull nomic-embed-text
```

Ожидаемый результат: pull дошёл до 100%.
Если не так: см. Шаг 5 инструкции [00-ollama.md](00-ollama.md) (прокси).

**LLM для Mem0 брать лёгкий.** Mem0 зовёт его на **каждой** операции с памятью для
извлечения фактов — тяжёлая модель замедлит всё. На DGX Spark брать MoE: `gpt-oss:20b`
(58 tok/s по [замерам](https://ollama.com/blog/nvidia-spark-performance)). Это **не**
обязано совпадать с основной моделью Hermes.

> ⚠️ **`embedding_dims`: в документации Mem0 дефолты расходятся** — 512 в Python-версии,
> 768 в TypeScript. `nomic-embed-text` выдаёт 768. **Не подставлять значение по памяти:**
> несовпадение размерности с векторным хранилищем ломается неочевидно (не падением, а
> странным поведением поиска). Не задавать `embedding_dims` вручную без необходимости.

---

## Стоп-условия

Немедленно остановись и доложи человеку, если:

1. **Возник соблазн `npm install hermes-agent`.** Пакет **НЕОФИЦИАЛЬНЫЙ** (мейнтейнер
   `wyrtensi`, **не Nous Research**; репозиторий `github.com/wyrtensi/hermes-agent-npm`;
   самоописание *«Unofficial npm bridge»*). **НИКОГДА не ставь его.** Проверено прямым
   запросом к реестру npm.
2. **Возник соблазн `pip install hermes-agent` / `uv tool install hermes-agent`.** PyPI-установки
   проект относит к **неподдерживаемым**, PR с исправлениями **приниматься не будут**.
   Пакет там есть и автор указан «Nous Research» — **это не делает установку поддерживаемой**.
3. **SHA256 served ≠ SHA256 repo** (Шаг 1) — **НЕ УСТАНАВЛИВАЙ**, доложи обе суммы.
4. **`ollama ps` показывает `CONTEXT` < 64000** — Hermes откажется стартовать. Чини **на стороне
   сервера Ollama** (`OLLAMA_CONTEXT_LENGTH=64000`). Через OpenAI-совместимый API это **не чинится**.
   Не пытайся «уговорить» Hermes на меньший контекст.
5. **~~Не угадывать `hermes config set model.base_url`~~ — снято.** Проверено вживую на
   `v2026.7.7.2`: сеттер работает с точечными ключами (Способ C в Шаге 4). В официальной
   документации он не описан, поэтому при отказе — откат на `hermes model` / правку yaml.
6. **Адреса недоступны** (`github.com`, `astral.sh`, `nodejs.org`, npm). Из России могут быть
   недоступны — тот же случай, что и с `ollama pull`. Недоступность `pypi.org`/`duckduckgo.com`
   стоп-условием **не является** (это предупреждения).
7. **Речь зашла об оплате Nous Portal.** На DGX он **не нужен**: локальная модель не требует ни
   OAuth, ни подписки, ни оплаты; Hermes ходит только на `localhost`. Не регистрируйся и не плати
   самостоятельно.

   > **NOT VERIFIED:** блокирует ли Nous Portal Россию — **выяснить не удалось**.
   > `portal.nousresearch.com` закрыт защитой Vercel и отдаёт HTTP 429 «We're verifying your
   > browser», из-за чего условия использования прочитать не получилось. В самом репозитории
   > **нет ни одного упоминания** гео-блокировок, санкций, OFAC или ограниченных стран — грепом
   > по всей документации ноль совпадений. **Не делай выводов ни в одну сторону**; если человек
   > соберётся платить — пусть сначала прочитает ToS из браузера.

### Стоп-условия по Telegram (Шаг 8)

8. **🚫 ПУБЛИЧНЫЕ ПРОКСИ ЗАПРЕЩЕНЫ.** Не ищи «free socks5 list», не бери прокси из выдачи,
   не подставляй чужой адрес. Цепочка последствий:

   ```
   токен бота → полный контроль над ботом → бот подключён к Hermes → у Hermes shell на машине
   ```

   Допустим **только** прокси, который контролирует человек. **Нет своего прокси — остановись
   и спроси.** Не иди искать.

9. **Токен бота — это пароль.** Не пиши его в файлы под git, в логи, в вывод команд, в
   транскрипт. Не эхай его в терминал. Только в `~/.hermes/.env`. Утёк — скажи человеку
   немедленно сделать `/revoke` у BotFather.

10. **Не выдумывай числовой Telegram ID и токен.** Оба приходят только от человека
    (@userinfobot и @BotFather). Примеры из документации (`123456789:ABCdef...`) —
    **не подставляй их как рабочие значения**.

11. **Не запускай шлюз без `TELEGRAM_ALLOWED_USERS`.** Формально шлюз и так откажет всем,
    но список должен быть выставлен **осознанно**, а не обнаружен постфактум.

12. **Hermes в песочнице NemoClaw + Telegram — не сочинять сетевую политику.**
    Стоп-условие снято: связка работает, но **только** через официальный пресет
    [`telegram`](https://github.com/NVIDIA/NemoClaw/blob/main/src/lib/messaging/channels/telegram/policy/hermes.yaml)
    (тир `open`; в `balanced` по умолчанию его нет).

    Запрещено: писать свои `network_policies` руками, расширять маршруты за пределы
    `/bot*/**`, добавлять хосты «на всякий случай», поднимать тир до `open` без ведома
    человека. Тир `open` меняет политику **всей песочницы**, а не только Telegram —
    это решение человека, а не побочный эффект настройки бота.

    Пресет не подошёл или его нет в твоей версии — **остановиться и спросить**,
    а не расширять политику вручную.

---

## Критерий готовности

Все проверки должны пройти.

**1–4. Автоматические:**

```bash
hermes --version                      # печатает версию
hermes doctor                         # не ругается
hermes config show | grep -F 'base_url: http://localhost:11434/v1'
ollama ps                             # колонка CONTEXT >= 64000
```

Машинно:

```bash
hermes --version >/dev/null 2>&1 && echo "VERSION_OK" || echo "VERSION_FAIL"
hermes doctor && echo "DOCTOR_OK" || echo "DOCTOR_FAIL"
hermes config show | grep -qF 'base_url: http://localhost:11434/v1' && echo "BASEURL_OK" || echo "BASEURL_FAIL"
ollama ps | awk 'NR>1 && $0 ~ /[0-9]/ {print}' | grep -qE '(6[4-9]|[7-9][0-9]|[1-9][0-9]{2,})[0-9]{3}' \
  && echo "CONTEXT_OK" || echo "CONTEXT_CHECK_MANUALLY"
```
Если `CONTEXT_CHECK_MANUALLY` — прочитай колонку `CONTEXT` в выводе `ollama ps` глазами и
сверь с порогом 64000 (в выводе значение может быть отформатировано).

**5–6. Запуск и РЕАЛЬНОЕ выполнение инструментов** — главный критерий.

Подготовь канарейку:

```bash
mkdir -p ~/hermes-check
echo 'CANARY-4F2A-HERMES-TOOLCALL-OK' > ~/hermes-check/canary.txt
cat ~/hermes-check/canary.txt
```

Запусти сессию и задай в ней ровно один вопрос:

```bash
hermes
```

Промпт в сессии:
```
Прочитай файл ~/hermes-check/canary.txt и напечатай его содержимое дословно.
```

**PASS, если:** в ответе появляется строка `CANARY-4F2A-HERMES-TOOLCALL-OK`, полученная
чтением файла.

**FAIL, если:** агент печатает **вызов инструмента текстом** (например, выводит JSON/XML-блок
вызова, `<tool_call>`, имя функции с аргументами) вместо того, чтобы файл прочитать, — и
канарейка не появляется. Это ровно тот симптом, который документация описывает как
*«tool calls won't work — the model will output tool calls as text»*.

**Если FAIL, то:**
- На **vLLM** — почти наверняка забыты `--enable-auto-tool-choice` и `--tool-call-parser hermes`
  (Шаг 7). Добавь и перезапусти сервер.
- На **Ollama** — проверь `CONTEXT >= 64000`, совпадение имени модели с `ollama list` и наличие
  `/v1` в `base_url`. Учти: парсер `hermes` рассчитан на Qwen 2.5 и Hermes 2/3 — модель должна
  уметь вызывать инструменты.

> **NOT VERIFIED:** неинтерактивного («одним промптом из shell») способа запуска Hermes в
> исходной инструкции **нет**. **Не угадывай флаг.** Выполняй проверку через TUI-сессию
> `hermes` и сверяй вывод с канарейкой.

Итоговый чек-лист:

- [ ] SHA256 served == SHA256 repo (Шаг 1)
- [ ] `hermes --version` печатает версию
- [ ] `hermes doctor` не ругается
- [ ] `hermes config show` показывает `base_url: http://localhost:11434/v1`
- [ ] `ollama ps` → в колонке `CONTEXT` не меньше 64000
- [ ] `hermes` запускается и отвечает
- [ ] агент **реально читает файлы**, а не печатает вызовы инструментов текстом (канарейка)

**7. Telegram — только если выполнялся Шаг 8.**

```bash
hermes gateway status && echo "GATEWAY_OK" || echo "GATEWAY_FAIL"
grep -q '^TELEGRAM_ALLOWED_USERS=..*' ~/.hermes/.env && echo "ALLOWLIST_OK" || echo "ALLOWLIST_MISSING"
```

Проверка на утечку токена — **должна быть пустой**:

```bash
cd ~/.hermes 2>/dev/null && git ls-files 2>/dev/null | xargs -r grep -lE '[0-9]{8,10}:[A-Za-z0-9_-]{35}' ; echo "TOKEN_LEAK_CHECK_DONE"
```

Проверки, которые может сделать **только человек** (не пытайся выполнить их сам):

- [ ] бот отвечает ему в Telegram
- [ ] `/whoami` в чате показывает уровень доступа
- [ ] **бот НЕ отвечает с постороннего аккаунта**, которого нет в `TELEGRAM_ALLOWED_USERS`
- [ ] на опасную команду приходит запрос подтверждения (`yes`/`no`)

Инварианты, которые обязаны выполняться:

- [ ] `TELEGRAM_ALLOWED_USERS` выставлен осознанно, значение получено от человека
- [ ] токен бота **не** попал в git, логи и транскрипт
- [ ] публичные прокси **не** использовались
- [ ] если прокси всё же нужен — он принадлежит человеку и проверен через `curl --socks5`
