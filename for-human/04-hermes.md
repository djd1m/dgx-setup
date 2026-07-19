# 04. Hermes Agent (Nous Research)

Требуется: выполненная инструкция [00-ollama.md](00-ollama.md).

Hermes — самообучающийся агент от [Nous Research](https://github.com/NousResearch/hermes-agent).
Лицензия MIT. Версия на момент написания — **0.18.2**.

Дословно из [README](https://raw.githubusercontent.com/NousResearch/hermes-agent/main/README.md):

> It's the only agent with a built-in learning loop — it creates skills from experience,
> improves them during use, nudges itself to persist knowledge, searches its own past
> conversations, and builds a deepening model of who you are across sessions.

Умеет: терминальный TUI, шлюз в мессенджеры (Telegram, Discord, Slack, WhatsApp, Signal),
планировщик задач, делегирование субагентам.

---

## Три способа запуска — не перепутай

Hermes можно развернуть по-разному, и это первое, что стоит решить.

| Способ | Где живёт **сам Hermes** | Когда брать |
|---|---|---|
| **curl-инсталлятор** (эта инструкция) | **на хосте**, venv в `~/.hermes/` | по умолчанию |
| Официальный образ `nousresearch/hermes-agent` | в контейнере, данные в `/opt/data` | свой Docker |
| **Через [NemoClaw](03-nemoclaw.md)** | **в песочнице OpenShell** | нужна изоляция всего агента |

### Четвёртый слой, который путают чаще всего

Отдельно от этого у Hermes настраивается **terminal backend** — он решает, где выполняются
**команды агента**, а не где живёт сам Hermes. Их шесть: `local`, `docker`, `ssh`,
`singularity`, `modal`, `daytona`.

То есть Hermes может стоять на хосте, а команды гонять в контейнере:

```yaml
terminal:
  backend: docker
```

Дословно: *«the agent runs on your host but executes every command inside a single,
persistent Docker sandbox»* — [docker.md](https://github.com/NousResearch/hermes-agent/blob/main/website/docs/user-guide/docker.md).

**Практический вывод.** Если задача — «чтобы агент не сломал систему командой», хватает
`backend: docker`, и NemoClaw не нужен. NemoClaw добавляет другое: изоляцию **самого
процесса** Hermes и **сетевую политику**.

### Вариант с NemoClaw

Если всё же нужен NemoClaw — Hermes там запускается **внутри песочницы OpenShell**.
Дословно: *«Create a **sandboxed** Hermes agent, then chat with it from the dashboard or
terminal»* — [quickstart NemoClaw для Hermes](https://docs.nvidia.com/nemoclaw/user-guide/hermes/get-started/quickstart.md).

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

Управление — через `nemohermes`, это *«the NemoClaw CLI with Hermes pre-selected»*:

```bash
nemohermes my-hermes status
nemohermes my-hermes logs --follow
nemohermes my-hermes rebuild
```

⚠️ **Взвесь, надо ли оно тебе.** Hermes — версия 0.18.2, лицензия MIT, платформа Tier 1.
NemoClaw — **alpha 0.1.0**, авторы сами пишут *«interfaces can change between releases»*,
а установщик не пинится по хэшу. Ты добавляешь незрелый слой ради изоляции, у которой
вдобавок есть [известная оговорка](03-nemoclaw.md) (issue #3280). Если не уверен —
бери Hermes сам по себе с `backend: docker`.

### Telegram в песочнице: работает, но нужен пресет

Раньше здесь стоял `NOT VERIFIED`. **Теперь проверено — и ответ хороший.**

У OpenShell сетевая политика **deny-by-default**, поэтому само по себе обращение к
`api.telegram.org` из песочницы не пройдёт. Но у NemoClaw есть **официальный пресет
именно под это** — файл
[`src/lib/messaging/channels/telegram/policy/hermes.yaml`](https://github.com/NVIDIA/NemoClaw/blob/main/src/lib/messaging/channels/telegram/policy/hermes.yaml)
в репозитории NVIDIA:

```yaml
preset:
  name: telegram
  description: "Hermes Telegram Bot API access"

network_policies:
  telegram:
    endpoints:
      - host: api.telegram.org
        port: 443
        protocol: rest
        enforcement: enforce
        rules:
          - allow: { method: GET,  path: "/bot*/**" }
          - allow: { method: POST, path: "/bot*/**" }
          - allow: { method: GET,  path: "/file/bot*/**" }
    binaries:
      - { path: /usr/local/bin/node }
      - { path: /usr/bin/python3* }
      - { path: /opt/hermes/.venv/bin/python }
```

Обрати внимание, насколько политика узкая: разрешён один хост, один порт и только
маршруты вида `/bot*/**` — и только трём конкретным бинарям. Это не «открыть интернет»,
а «пустить Hermes к Telegram Bot API».

⚠️ **Но по умолчанию он не включён.** В
[`nemoclaw-blueprint/policies/tiers.yaml`](https://github.com/NVIDIA/NemoClaw/blob/main/nemoclaw-blueprint/policies/tiers.yaml)
Telegram присутствует **только в тире `open`**:

| Тир | Telegram |
|---|---|
| `restricted` | ❌ |
| `balanced` (**по умолчанию**) | ❌ |
| `open` | ✅ `{ name: telegram, access: read-write }` |

Так что при onboarding надо **выбрать пресет Telegram** (либо добавить эквивалентные
правила), иначе бот молча не достучится — и симптом будет неотличим от того, что описан
ниже в разделе про блокировку у провайдера. Сначала проверь пресет, потом ищи DNS.

Вариант «Hermes на хосте + `backend: docker`» по-прежнему проще: сеть не ограничена,
воевать не с чем. Но теперь это вопрос удобства, а не «неизвестно, заработает ли».

---

## 🚨 Первое и самое важное: не ставь его из npm

**В npm есть пакет `hermes-agent`, и он к Nous Research отношения не имеет.**

Проверено прямым запросом к реестру npm:

| | |
|---|---|
| Мейнтейнер | `wyrtensi <wyrtensi@gmail.com>` — **не Nous Research** |
| Репозиторий | `github.com/wyrtensi/hermes-agent-npm` — **не официальный** |
| Собственное описание | *«**Unofficial** npm bridge for Hermes Agent 0.18.2»* |

Nous Research **нигде не документирует** установку через npm. Не ставь этот пакет.

**Из PyPI тоже не ставь.** Пакет `hermes-agent` 0.18.2 там есть, автор указан «Nous Research»,
но документация проекта прямо относит такие установки к **неподдерживаемым**:

> Unsupported: installs via `pypi` (e.g. `uv tool install hermes-agent`, `pip install hermes-agent`, etc.)

и добавляет, что PR с исправлениями **приниматься не будут** —
[platform-support.md](https://raw.githubusercontent.com/NousResearch/hermes-agent/main/website/docs/getting-started/platform-support.md).

**Единственный правильный способ — curl-инсталлятор из Шага 1.**

---

## Шаг 0. Требования

Вопреки распространённому мнению, **Hermes — это Python, а не Node**:

| Что | Версия | Зачем |
|---|---|---|
| **Python** | **3.11** | сам Hermes. Ставится автоматически через `uv` |
| Node.js | 22 | **только** для браузерной автоматизации и моста WhatsApp |
| Git | любой | **единственное настоящее требование** |

На Linux пригодятся `curl` и `xz-utils` (Node качается архивом `.tar.xz`).

**Твоя платформа — Tier 1:** *«Linux / WSL2 (x86_64, aarch64)»*, тестируется на свежей Ubuntu.

---

## Шаг 1. Установка

```bash
curl -fsSL https://hermes-agent.nousresearch.com/install.sh | bash
```

Затем:

```bash
source ~/.bashrc
hermes
```

### Проверка цепочки поставки

Скрипт по этому адресу **побайтово совпадает** с исходником в репозитории:

```
SHA256: c2e4326c1660bd45f64321996eb15bda35e7a4649e32a310495a61972a2804c8
Строк:  3133
```

**Проверь сам — до установки, а не после:**

```bash
curl -fsSL https://hermes-agent.nousresearch.com/install.sh | sha256sum
curl -fsSL https://raw.githubusercontent.com/NousResearch/hermes-agent/main/scripts/install.sh | sha256sum
```

Две команды должны дать **одинаковый** результат. Первая — то, что тебе отдаёт сайт; вторая —
то, что лежит в репозитории. Совпадают — значит сайт отдаёт ровно код из репозитория.

> 🛑 **Если суммы НЕ совпали — не устанавливай.** Это значит, что скрипт с сайта отличается
> от исходника в репозитории, а ты собираешься выполнить его **через `| bash`**, то есть
> отдать ему свою машину. Не «попробуй всё равно», не «наверное, кэш». Остановись и разберись,
> откуда расхождение.
>
> *(Само значение выше — на момент написания; с новыми версиями оно закономерно изменится.
> Проверяется не совпадение с ним, а совпадение **двух команд между собой**.)*

### Для DGX без монитора — добавь `--skip-browser`

```bash
curl -fsSL https://hermes-agent.nousresearch.com/install.sh | bash -s -- --skip-browser
```

Это пропускает скачивание Chromium и Playwright — а заодно единственный шаг, которому
реально нужен root. Из документации: *«The only thing on the install path that genuinely
needs root is Playwright's `--with-deps` step»*.

Остальные флаги: `--skip-setup`, `--no-venv`, `--branch NAME`, `--commit SHA`, `--dir PATH`,
`--hermes-home PATH`, `--non-interactive`.

### Куда всё ставится

| Режим | Код | Бинарник | Данные |
|---|---|---|---|
| Обычный | `~/.hermes/hermes-agent/` | `~/.local/bin/hermes` | `~/.hermes/` |
| От root | `/usr/local/lib/hermes-agent/` | `/usr/local/bin/hermes` | `/root/.hermes/` |

**sudo для основной установки не нужен.** Python приходит через `uv` без прав root.
sudo используется только для системных пакетов, и скрипт корректно переживает его отсутствие —
просто напечатает команду, которую надо выполнить администратору.

### Откуда качает

`github.com`, `astral.sh` (uv), `nodejs.org`, npm, Chromium (если не отключить).
Установщик ещё проверяет доступность `pypi.org` и `duckduckgo.com` — но это **предупреждения,
а не ошибки**: при недоступности он продолжит, сообщив, что веб-поиск и часть зависимостей
могут не работать.

Из России эти адреса могут быть недоступны — тот же случай, что и с `ollama pull`.

---

## Шаг 2. Подключить к Ollama

Через мастер:

```bash
hermes model
```

Выбери **«Custom endpoint (self-hosted / VLLM / etc.)»**, укажи `http://localhost:11434/v1`,
ключ пропусти, введи имя модели.

> ⚠️ `hermes model` **нельзя запускать внутри чата**. Только отдельной командой.
> Команда `/model` внутри сессии умеет лишь переключаться между уже настроенными провайдерами.

Либо правкой `~/.hermes/config.yaml`:

```yaml
model:
  default: qwen3-coder:30b
  provider: custom
  base_url: http://localhost:11434/v1
  context_length: 64000
```

Имя модели должно совпадать с выводом `ollama list`.

> **NOT VERIFIED:** команда `hermes config set model.base_url <url>` в документации нигде
> не приведена. Официально сказано: *«For other providers and custom endpoints, use
> `hermes model` or set `model.base_url` in `config.yaml` directly»*. Плюс оговорка:
> *«`hermes config set` only writes scalar values»*. **Не угадывай сеттер** — пользуйся
> мастером или правь yaml.

---

## 🔥 Шаг 3. Контекст 64000 — иначе Hermes просто не запустится

Это, по словам самой документации, **«источник путаницы №1»**.

**Hermes требует контекст не меньше 64000 токенов и отвергает меньший прямо на старте.**
А Ollama по умолчанию даёт **4096** при небольшом объёме памяти.

Через OpenAI-совместимый API это **не чинится** — только на стороне сервера Ollama.
Если ты выполнял [00-ollama.md](00-ollama.md), строка уже стоит в `ollama.service`:

```ini
Environment="OLLAMA_CONTEXT_LENGTH=64000"
```

Разово:

```bash
OLLAMA_CONTEXT_LENGTH=64000 ollama serve
```

Проверка — колонка `CONTEXT`:

```bash
ollama ps
```

Помни: контекст 64k занимает память **сверх** веса модели. На DGX Spark с ~119 ГБ единой памяти это не ограничение.

---

## Шаг 4. vLLM вместо Ollama? На DGX Spark — нет

Документация Hermes описывает vLLM подробнее, чем Ollama, и от этого возникает соблазн.
**На DGX Spark ему поддаваться не стоит** — разбор целиком в
[08-vllm-vs-ollama.md](08-vllm-vs-ollama.md), здесь коротко:

- **Быстрее не будет.** Преимущество vLLM — батчинг при множестве параллельных запросов;
  у тебя один пользователь, и оба движка упрутся в одну шину 273 ГБ/с.
- **Открытый [баг #46307](https://github.com/vllm-project/vllm/issues/46307) на GB10**
  вешает хост целиком: *«SSH dies; the machine requires a hard power-cycle»*.
- [Официальный playbook NVIDIA для кодинг-агентов на DGX Spark](https://github.com/NVIDIA/dgx-spark-playbooks/blob/main/nvidia/cli-coding-agent/README.md)
  построен на Ollama; vLLM в нём не упомянут.

Типичный совет из интернета — `--tensor-parallel-size 2` — **к этой машине неприменим**:
GB10 это единый чип, GPU **один**, распределять модель не по чему.

**Если всё-таки запускаешь vLLM** (на другом железе или осознанно, прочитав 08):

```bash
vllm serve <модель> --port 8000 --max-model-len 65536 \
  --enable-auto-tool-choice --tool-call-parser hermes
```

Три вещи, каждая из которых ломается тихо:

> ⚠️ **`--enable-auto-tool-choice` и `--tool-call-parser` обязательны.** Без них, дословно:
> *«tool calls won't work — the model will output tool calls as text»* — агент будет
> печатать вызовы инструментов текстом вместо их выполнения. Парсер `hermes` подходит
> для Qwen 2.5 и Hermes 2/3.

> ⚠️ **`--max-model-len` — это и есть контекст на vLLM.** `OLLAMA_CONTEXT_LENGTH` здесь
> не действует: Ollama в этой ветке не участвует. Помни требование из Шага 3 — **Hermes
> не стартует ниже 64000**. `65536` его покрывает; забудешь флаг — упрёшься в тот самый
> отказ, который Hermes называет «источником путаницы №1».

Дальше `base_url: http://localhost:8000/v1`.

**Вывод: оставайся на Ollama.** Скорость на этой машине даёт не движок, а
[выбор MoE-модели](00-ollama.md) — разница десятикратная, движок такого не даст.

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

Если модель отвечает медленно и всё падает по таймауту — в `~/.hermes/.env`:

```
HERMES_API_TIMEOUT=1800
```

Это **только переменная окружения**, в `config.yaml` такого ключа нет.

---

## Шаг 5. Подключить Telegram-бота

Источник — [официальная страница](https://github.com/NousResearch/hermes-agent/blob/main/website/docs/user-guide/messaging/telegram.md).

### 1. Создать бота

В Telegram найди **@BotFather**, отправь `/newbot`, придумай отображаемое имя и username
(обязан заканчиваться на `bot`). В ответ придёт токен вида `123456789:ABCdefGHIjklMNOpqrSTUvwxYZ`.

> 🔒 **Токен = полный контроль над ботом.** Дословно: *«Keep your bot token secret. Anyone
> with this token can control your bot.»* Утёк — немедленно `/revoke` у BotFather.
> В git не коммить.

### 2. Узнать свой числовой ID

Напиши **@userinfobot** — он мгновенно ответит числом вроде `123456789`.

Нужно именно **число**, не `@username`. ID постоянный и не меняется.

### 3. Настроить

Через мастер:

```bash
hermes gateway setup
```

Либо руками в `~/.hermes/.env`:

```bash
TELEGRAM_BOT_TOKEN=123456789:ABCdefGHIjklMNOpqrSTUvwxYZ
TELEGRAM_ALLOWED_USERS=123456789
```

Несколько пользователей — через запятую.

### 4. Запустить

```bash
hermes gateway
```

| Команда | Что делает |
|---|---|
| `hermes gateway` | запустить |
| `hermes gateway status` | проверить |
| `hermes gateway stop` | остановить |
| `hermes gateway restart` | перезапустить |

Напиши боту в Telegram — он должен ответить.

---

## ✅ Про безопасность бота — тут авторы молодцы

Телеграм-бот — это дверь в твой DGX, открытая наружу. Hermes выполняет команды; если бот
найдут посторонние, они будут разговаривать с агентом, у которого есть shell.

**Но список разрешённых работает fail-closed.** Дословно:

> Always set `TELEGRAM_ALLOWED_USERS` to restrict who can interact with your bot.
> **Without it, the gateway denies all users by default as a safety measure.**

То есть забыл настроить — бот **не ответит никому**, включая тебя. Ошибка приводит к
«слишком закрыто», а не «открыто всему интернету». Это правильное поведение — сравни
с [Ouroboros](05-ouroboros.md), где защита при сбое, наоборот, **пропускает** команды.

Проверить свой уровень доступа прямо в чате:

```
/whoami
```

**Опасные команды требуют подтверждения в Telegram.** Агент спросит — отвечаешь `yes` или `no`.

Ограничить набор команд для не-админов:

```yaml
gateway:
  platforms:
    telegram:
      extra:
        allow_from:
          - "123456789"
        allow_admin_from:
          - "123456789"
        user_allowed_commands:
          - status
          - model
```

---

## Три грабли с Telegram

### 1. Docker-бэкенд + вложения

Если включил `terminal.backend: docker` — вложения уходят **с хоста, а не из контейнера**.
Файл, созданный агентом внутри, наружу не отправится, пока не прокинешь папку:

```yaml
terminal:
  backend: docker
  docker_volumes:
    - "/home/user/.hermes/cache/documents:/output"
```

### 2. Бот молчит в группе

Виноват Privacy Mode. Выключается у BotFather: `/mybots` → свой бот → Bot Settings →
Group Privacy → Turn off. **Но одного этого мало:**

> You must remove and re-add the bot to any group after changing the privacy setting.

Telegram кэширует настройку в момент вступления бота — без переподключения не подхватится.

### 3. «Не могу достучаться до api.telegram.org, нужен SOCKS5»

Hermes пишет, что не видит эндпоинт Telegram и просит SOCKS5. **Не спеши поднимать прокси.**

#### ✅ Сначала — одна строка. В России этого хватает

```bash
TELEGRAM_FALLBACK_IPS=149.154.167.220
```

Добавь в `~/.hermes/.env`, затем `hermes gateway restart`.

**Проверено на живой установке в России (июль 2026): помогло, прокси не понадобился.**
*(Одна машина, один провайдер, один момент времени — не закон природы, но начинать
стоит отсюда: это одна строка против получаса возни с прокси.)*

#### Что это говорит о причине

Важная деталь: по имени `api.telegram.org` не работает, а по **сырому IP** — работает.
Значит, провайдер режет **DNS**, а не сам адрес. Отсюда и лечение: не ходить в DNS вовсе.

Причина, соответственно, не в Hermes и не в Telegram. **Telegram Россию обслуживает** —
это ровно тот же случай, что с `ollama pull` и Cloudflare: сервис тебе рад, до него не
доходит трафик.

#### Если не помогло — тогда SOCKS5

У Hermes есть свой параметр, и **socks5 поддерживается**:

```bash
TELEGRAM_PROXY=socks5://127.0.0.1:10808
```

Работают и обычные `HTTPS_PROXY` / `HTTP_PROXY` / `ALL_PROXY`.

### 🚫 Публичные прокси для этого использовать нельзя

Соблазн понятен: нашёл в поиске «free socks5 list» — и готово. **Не делай этого.**
Посчитай, что ты отдаёшь чужому серверу:

```
токен бота → полный контроль над ботом → бот подключён к Hermes → у Hermes shell на твоей машине
```

Публичные прокси держат неизвестные люди. Заметная часть их существует ради сбора трафика,
многие — honeypot'ы. К Telegram идёт HTTPS, и внутри TLS токен не прочитать, — но встраивать
постороннего в цепочку, ведущую к машине с shell-доступом, не стоит ради экономии получаса.
Плюс они постоянно отваливаются, и ты будешь искать поломку в Hermes.

**Правильно — свой прокси.** Если у тебя есть VPS с xray/v2ray, клиент на этой машине
поднимает локальный SOCKS5 (обычно `127.0.0.1:10808`), и в `TELEGRAM_PROXY` идёт он.
Проверить, что прокси живой, до всякого Hermes:

```bash
curl -s --socks5 127.0.0.1:10808 https://api.ipify.org; echo
```

Должен показать IP твоего сервера, а не твой домашний. Показал — можно настраивать Hermes.

> **Что известно про доступность `api.telegram.org` из России.** Проверено на одной машине
> в июле 2026: **по имени не работает, по IP `149.154.167.220` работает** — то есть режется
> DNS. `TELEGRAM_FALLBACK_IPS` эту ситуацию лечит, прокси не потребовался. Это одна точка
> данных, у другого провайдера картина может отличаться — но порядок действий тот же:
> сначала fallback IP, прокси только если не помогло.

### Таблица неполадок

| Симптом | Причина |
|---|---|
| Не отвечает вообще | неверный `TELEGRAM_BOT_TOKEN`, смотри логи |
| «Unauthorized» | твоего ID нет в `TELEGRAM_ALLOWED_USERS` — сверься с @userinfobot |
| Молчит в группе | Privacy Mode включён, см. грабли №2 |
| Голос приходит файлом, а не кружком | не установлен `ffmpeg` |

---

## Несколько ботов на одной машине — и когда это вообще нужно

Hermes умеет держать **несколько независимых агентов на одной машине** — это штатная фича
«профилей». Каждый профиль — отдельный агент со своим `HERMES_HOME`: своя конфигурация,
свой `.env` (а значит **свой токен бота**), своя память и персона, свои скиллы, свой процесс
и systemd-сервис. Код при этом общий, ставится один раз. Источники:
[profiles.md](https://github.com/NousResearch/hermes-agent/blob/main/website/docs/user-guide/profiles.md),
[multi-profile-gateways.md](https://github.com/NousResearch/hermes-agent/blob/main/website/docs/user-guide/multi-profile-gateways.md).

### Рецепт на второй (и каждый следующий) бот

```bash
hermes profile create personal-bot        # заведёт ~/.hermes/profiles/personal-bot/
hermes -p personal-bot gateway setup       # свой .env: свой TELEGRAM_BOT_TOKEN + TELEGRAM_ALLOWED_USERS
hermes -p personal-bot gateway install     # свой сервис hermes-gateway-personal-bot.service
hermes -p personal-bot gateway start
```

После `profile create` у профиля появляется и удобный алиас-команда с его именем:
`personal-bot gateway status` — то же, что `hermes -p personal-bot gateway status`.

Что разъезжается по инстансам **автоматически** (всё скоупится по `HERMES_HOME`):

| Что | Инстанс 1 (дефолтный) | Инстанс 2 |
|---|---|---|
| Каталог | `~/.hermes/` | `~/.hermes/profiles/personal-bot/` |
| `.env` (токен, allowlist) | свой | свой |
| Память + персона (`MEMORY.md`/`SOUL.md`) | своя | своя |
| systemd-сервис | `hermes-gateway` | `hermes-gateway-personal-bot` |
| Порт | не нужен (polling) | не нужен (polling) |

Руками делаешь только одно: **свой токен бота на каждого** (заведи каждого отдельно у
@BotFather) и **свой числовой ID** в его `TELEGRAM_ALLOWED_USERS`. Одинаковый токен на два
профиля Hermes **отвергает на старте** («same-token conflict»): два поллинга одного бота —
это конфликт на стороне Telegram, а не Hermes.

**Порт не занимается.** Telegram работает через long polling (исходящий `getUpdates`),
поэтому боты не слушают порт и между собой за него не дерутся — хоть пять штук. Порт нужен
только в опциональном webhook-режиме (по умолчанию выключен) — вот там второму боту
пришлось бы дать свой `TELEGRAM_WEBHOOK_PORT`.

> 🇷🇺 **В России** строку `TELEGRAM_FALLBACK_IPS=149.154.167.220` из раздела выше добавляй в
> `.env` **каждого** профиля отдельно — файлы не общие.

### Нужен ли контейнер?

Коротко: **чтобы просто запустить несколько ботов — нет. Чтобы боты были для разных
людей — да.**

- **Несколько твоих собственных ботов** — спокойно на хосте через профили. Контейнеризировать
  ничего не надо.
- **Боты для разных людей на одном сервере** — контейнер (или OpenShell) **обязателен**, и это
  прямое требование [SECURITY.md](https://github.com/NousResearch/hermes-agent/blob/main/SECURITY.md)
  проекта. Причина: при дефолтном `terminal.backend: local` команды агента исполняются **как твой
  хостовый пользователь, с его полными правами**. То есть каждый, кому разрешён бот, фактически
  получает shell на сервере — и может дотянуться до каталогов `~/.hermes/profiles/*` **других**
  ботов: их токенов, `.env`, сессий.

> ⚠️ **Ловушка, на которой легко обжечься.** `terminal.backend: docker` эту дыру **не
> закрывает**. Он песочит только shell-команды агента, а сам процесс Hermes (исполнение кода,
> MCP, плагины, хуки, скиллы) остаётся на хосте. Против честного-но-ошибающегося агента годится;
> против **враждебного** вызывающего — нет. Так и написано в SECURITY.md §2.2.

Радиус поражения по схемам:

| Схема | Что изолировано | Что может натворить чужой/захваченный бот |
|---|---|---|
| Хост + `backend: local` (дефолт) | ничего | shell как хостовый юзер → вся машина + `~/.hermes/profiles/*` чужих ботов |
| Хост + `backend: docker` | только shell-команды агента | процесс Hermes всё ещё на хосте: код, MCP, плагины, хуки — мимо песочницы |
| Контейнер на бота (офиц. образ) / OpenShell | весь процесс агента | ограничен своим контейнером — **это и есть поддерживаемая схема** для чужого ввода |

Что предписывает сам проект для мультитенанта (§2.2, §2.6.4): отдельный инстанс + свой
allowlist на каждого, и **whole-process wrapping** — либо официальный образ
`nousresearch/hermes-agent` (по контейнеру на бота), либо NVIDIA OpenShell. Не хостовый
`local` и **не просто** `docker`-бэкенд.

> **NOT VERIFIED:** готового multi-container compose в репозитории нет — схему «по контейнеру
> на бота» собираешь сам из контракта `HERMES_HOME`/volume (свой каталог хоста на `/opt/data`
> + свой токен на каждый контейнер; при `network_mode: host` развести порты дашборда/API).
> Пошагового рецепта «по отдельному Linux-пользователю на бота» в доках тоже нет — принцип
> описан, механика OS-пользователей — нет.

### Готовый пример: три бота для трёх людей (папа/жена/сын)

Типовой случай «разные люди на одном VPS» — это как раз про контейнер на каждого. Готовый
скелет: [`scripts/docker-compose.hermes-multi.example.yml`](../scripts/docker-compose.hermes-multi.example.yml).
Там три сервиса (`hermes-dad`/`hermes-wife`/`hermes-son`), у каждого свой том `/opt/data`
(= свой `HERMES_HOME`), свой файл `secrets/<человек>.env` со своим токеном и своим
`TELEGRAM_ALLOWED_USERS`. Коротко, что важно в этом примере:

- **host-networking не используется** (в отличие от LiteLLM-примера): Telegram — это исходящий
  long polling, входящие порты не нужны, а на общей сети контейнеры подрались бы за порты.
- **backend внутри контейнера остаётся `local`** — команды и так исполняются внутри контейнера,
  который и есть граница; docker-in-docker не нужен.
- **три разных токена** (одинаковый на два контейнера Hermes отвергнет), в allowlist у каждого —
  только его владелец: жена не пишет боту сына и наоборот.
- модель у каждого настраивается один раз через `hermes model` внутри его контейнера.

> ✅ **Сверено с живым образом (2026-07-19):** команда запуска — `["gateway", "run"]`, тег
> закреплён `v2026.7.7.2`, entrypoint (`/init`) трогать нельзя, а host-права пробрасываются через
> `HERMES_UID=$(id -u) HERMES_GID=$(id -g)` (не `--user`). Готового multi-container `compose` в репе
> Hermes нет — это по-прежнему скелет, но детали выверены по `Dockerfile`/`main-wrapper.sh`.
> Эмпирически осталось проверить только живой запуск на твоём VPS и что модель отвечает после
> `hermes model` в каждом контейнере (docker на VPS ещё не ставили).

### Целесообразность: когда несколько Hermes оправданы, а когда это лишнее

Тут легко перестараться. Многое, ради чего плодят инстансы, **один Hermes уже умеет сам:**

- быть в **Telegram + Discord + Slack одновременно** — один шлюз держит все каналы разом;
- **разные модели на разные задачи** — `/model` переключает модель прямо в сессии, суб-агенту
  можно задать свою;
- **много параллельных диалогов/пользователей** — сессии заводятся по чату, по умолчанию без
  лимита;
- **долгие задачи не блокируют чат** — `/background` и `delegate_task` (суб-агенты).

Отдельный инстанс реально нужен только когда должно **одновременно** различаться то, чего в
одном Hermes ровно **по одной штуке**:

| Зачем | Отдельный инстанс? | Почему |
|---|---|---|
| Своя постоянная память + персона (рабочий ассистент / кодер / умный дом) | **Да** | `MEMORY.md`/`USER.md`/`SOUL.md` — по одной на инстанс; `/personality` — лишь оверлей промпта в сессии, не отдельная память |
| Разная песочница исполнения **одновременно** (docker-«опасный» агент и read-only) | **Да** | `terminal.backend` — одно значение на инстанс; суб-агенты наследуют бэкенд родителя |
| Настоящий lockdown прав (бот «только статус» vs бот с полным shell) | **Да** | admin/user-разделение гейтит только слэш-команды; обычный чат всё равно несёт доступ к терминалу |
| Крэш-изоляция (один агент зациклился — другой жив) | **Да** | режим «процесс на профиль» даёт независимые домены отказа |
| Отдельная личность бота для разной аудитории | **Да** | токен — по одному на платформу на профиль |
| Просто ещё один канал (Telegram + Discord) | Нет | один шлюз держит все каналы |
| Разные модели на задачи | Нет | `/model` в сессии + модель у суб-агента |
| Параллельность / много пользователей | Нет | конкурентные сессии, `/background`, `delegate_task` |

Цена нескольких инстансов: N процессов и N systemd-юнитов, N токенов ротировать, память
**не** общая между профилями (`MEMORY`/`USER`/`SOUL` у каждого свои). Если инстансов правда
несколько, но одновременная крэш-изоляция не нужна — есть режим `multiplex_profiles`: один
процесс обслуживает все профили, сохраняя изоляцию конфига/памяти/токенов, но теряя
независимые домены отказа.

**Вывод:** 2–3 профиля под честно разных агентов (запертый бот умного дома, docker-песочный
кодер, семейный бот со своим токеном) — оправданно. Поднимать второй инстанс ради ещё одного
канала, модели или параллельности — оверинжиниринг: это уже умеет один.

---

## Память: Mem0 OSS — полностью локально, без облака

Встроенная память Hermes — это **профиль, а не корпус знаний**: `MEMORY.md` ограничен
~2200 символами, `USER.md` — ~1375. При переполнении инструмент возвращает ошибку, и агент
сам расчищает место. Для «помни, что я предпочитаю pytest» этого хватает. Для «знай
содержимое моих ста заметок» — нет.

Встроенного RAG у Hermes **нет**. Штатный путь — внешние memory-провайдеры, и почти все
они облачные, с API-ключом. **Кроме одного.**

**Mem0 в режиме OSS работает целиком на твоей машине.** Дословно из
[документации интеграции Mem0 с Hermes](https://docs.mem0.ai/integrations/hermes):

> No data is sent to Mem0 Cloud, and no Mem0 API key is required

То есть: LLM — твоя Ollama, эмбеддинги — твоя Ollama, векторное хранилище — локальный
Qdrant в файле. Ни ключа, ни аккаунта, ни исходящего трафика. Для твоей ситуации с
гео-ограничениями это принципиально: остальные провайдеры (Honcho, Supermemory, Mem0 Cloud…)
упрутся в ключ и заграничный сервис.

### Настройка

Конфиг живёт в `~/.hermes/mem0.json`. Интерактивно:

```bash
hermes memory setup mem0 --mode oss \
  --oss-llm ollama \
  --oss-embedder ollama \
  --oss-vector qdrant
```

Структура файла — дословный пример из документации (он там **с OpenAI**, показываю как есть):

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

Под Ollama меняются два блока. Имена провайдеров и ключи — из
[документации LLM](https://docs.mem0.ai/components/llms/models/ollama) и
[документации эмбеддера](https://docs.mem0.ai/components/embedders/models/ollama):

```json
{
  "mode": "oss",
  "oss": {
    "llm": {"provider": "ollama", "config": {"model": "gpt-oss:20b"}},
    "embedder": {"provider": "ollama", "config": {"model": "nomic-embed-text"}},
    "vector_store": {"provider": "qdrant", "config": {"path": "~/.hermes/mem0_qdrant"}}
  }
}
```

> **NOT VERIFIED:** дословный пример в документации Mem0 — **с OpenAI**. Вариант с Ollama
> выше собран из документированных имён провайдеров и ключей, но **как готовый JSON для
> Hermes он в документации не приведён**. Проверь на месте; если не заведётся — сверяйся
> с `hermes memory setup mem0`, а не правь наугад.

### Три вещи, о которых легко забыть

**Модель эмбеддингов надо скачать отдельно.** Она не та же, что основная:

```bash
ollama pull nomic-embed-text
```

**LLM для Mem0 — не обязательно тот же, что основной.** Mem0 зовёт его на **каждой**
операции с памятью, чтобы извлечь факты. Тяжёлая модель здесь замедлит всё. На DGX Spark
логично взять что-то из MoE полегче — `gpt-oss:20b` даёт 58 tok/s.

**⚠️ Осторожно с `embedding_dims`.** В документации Mem0 дефолт **расходится**: 512 в
Python-версии и 768 в TypeScript. При этом `nomic-embed-text` выдаёт 768. Несовпадение
размерности с векторным хранилищем ломается неочевидно — если Mem0 ведёт себя странно,
проверь это в первую очередь. Не угадывай: посмотри фактическую размерность своей модели.

---

## Про Nous Portal — не нужен

У Nous есть платный Portal, но **на DGX он тебе ни к чему**: локальная модель не требует
ни OAuth, ни подписки, ни оплаты. Hermes будет ходить только на `localhost`.

> **NOT VERIFIED:** блокирует ли Nous Portal Россию — выяснить не удалось.
> `portal.nousresearch.com` закрыт защитой Vercel и отдаёт HTTP 429 «We're verifying your
> browser», из-за чего условия использования прочитать не получилось. В самом репозитории
> **нет ни одного упоминания** гео-блокировок, санкций, OFAC или ограниченных стран —
> грепом по всей документации ноль совпадений. Не делай выводов ни в одну сторону;
> если соберёшься платить — сначала прочитай ToS из браузера.

---

## Готово, если

- [ ] `hermes --version` печатает версию
- [ ] `hermes doctor` не ругается
- [ ] `hermes config show` показывает `base_url: http://localhost:11434/v1`
- [ ] `ollama ps` → в колонке `CONTEXT` не меньше 64000
- [ ] `hermes` запускается и отвечает
- [ ] агент реально читает файлы, а не печатает вызовы инструментов текстом

Если подключал Telegram:

- [ ] `hermes gateway status` — работает
- [ ] бот отвечает тебе в Telegram
- [ ] `/whoami` в чате показывает твой уровень доступа
- [ ] **бот НЕ отвечает с постороннего аккаунта, которого нет в `TELEGRAM_ALLOWED_USERS`** — проверь это отдельно
- [ ] на опасную команду приходит запрос подтверждения
- [ ] токен бота не попал в git
