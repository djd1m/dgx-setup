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

Помни: контекст 64k ест видеопамять **сверх** веса модели.

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
