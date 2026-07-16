# 04. Hermes Agent (Nous Research) — рецепт для ИИ-агента

**Цель:** установить Hermes Agent 0.18.2 ([NousResearch/hermes-agent](https://github.com/NousResearch/hermes-agent), MIT)
на x86_64 Ubuntu/DGX-OS без монитора, подключить к локальной Ollama и убедиться, что
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
   даёт **4096** на картах меньше 24 ГБ. Через OpenAI-совместимый API это **не чинится** —
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

> Помни: контекст 64k ест видеопамять **сверх** веса модели.

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

> **NOT VERIFIED:** команда `hermes config set model.base_url <url>` в документации **нигде
> не приведена**. Официально сказано: *«For other providers and custom endpoints, use
> `hermes model` or set `model.base_url` in `config.yaml` directly»*. Плюс оговорка:
> *«`hermes config set` only writes scalar values»*.
> **НЕ УГАДЫВАЙ СЕТТЕР.** Пользуйся `hermes model` или правь yaml напрямую.

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

### Шаг 7. (Опционально) vLLM вместо Ollama

Документация Hermes описывает vLLM подробнее, и на многокарточном DGX он раскрывается лучше.

```bash
vllm serve meta-llama/Llama-3.1-70B-Instruct \
  --port 8000 --max-model-len 65536 --tensor-parallel-size 2 \
  --enable-auto-tool-choice --tool-call-parser hermes
```

> ⚠️ **`--enable-auto-tool-choice` и `--tool-call-parser hermes` ОБЯЗАТЕЛЬНЫ.** Без них,
> дословно: *«tool calls won't work — the model will output tool calls as text»* — агент будет
> **печатать вызовы инструментов текстом вместо их выполнения**. Парсер `hermes` подходит
> для Qwen 2.5 и Hermes 2/3.

`--tensor-parallel-size 2` — число карт. Ставь по факту.

Дальше `base_url: http://localhost:8000/v1`.

**Что выбрать.** Ollama проще и уже стоит. vLLM быстрее на нескольких картах и лучше
документирован для Hermes. **Начни с Ollama**, переезжай при нехватке скорости.

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
5. **Хочется угадать `hermes config set model.base_url`** — **NOT VERIFIED**, такой инвокации в
   документации нет. Используй `hermes model` или правь `config.yaml`.
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
