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

Хочешь убедиться сам:

```bash
curl -fsSL https://hermes-agent.nousresearch.com/install.sh | sha256sum
curl -fsSL https://raw.githubusercontent.com/NousResearch/hermes-agent/main/scripts/install.sh | sha256sum
```

Суммы должны совпасть. *(Значение выше — на момент написания; с новыми версиями оно изменится.
Важно, что две команды дают **одинаковый** результат.)*

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
А Ollama по умолчанию даёт **4096** на картах меньше 24 ГБ.

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

## Шаг 4. Альтернатива для DGX — vLLM вместо Ollama

Документация Hermes описывает vLLM подробнее, и на многокарточном DGX он раскрывается лучше:

```bash
vllm serve meta-llama/Llama-3.1-70B-Instruct \
  --port 8000 --max-model-len 65536 --tensor-parallel-size 2 \
  --enable-auto-tool-choice --tool-call-parser hermes
```

> ⚠️ **`--enable-auto-tool-choice` и `--tool-call-parser` обязательны.** Без них, дословно:
> *«tool calls won't work — the model will output tool calls as text»* — агент будет
> печатать вызовы инструментов текстом вместо их выполнения. Парсер `hermes` подходит
> для Qwen 2.5 и Hermes 2/3.

`--tensor-parallel-size 2` — число карт. Ставь по факту.

Дальше `base_url: http://localhost:8000/v1`.

**Что выбрать.** Ollama проще и уже стоит. vLLM быстрее на нескольких картах и лучше
документирован для Hermes. Начни с Ollama, переезжай при нехватке скорости.

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
