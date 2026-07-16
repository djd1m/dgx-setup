# 03. NemoClaw + OpenShell — рецепт для AI-агента

**Цель:** развернуть NemoClaw (CLI + чертёж развёртывания NVIDIA), который управляет песочницей
OpenShell, которая изолирует и запускает агента OpenClaw, на x86_64 Ubuntu/DGX-OS.
Провайдер инференса — **только Ollama**. Установка версии запинована на тег `v0.0.84`.

Предусловие-документ: выполнена инструкция [00-ollama.md](../for-human/00-ollama.md).

Что есть что (из [README](https://github.com/NVIDIA/NemoClaw)):
`NemoClaw ──управляет──> OpenShell ──изолирует и запускает──> OpenClaw / Hermes`.
NemoClaw — не агент и не модель. Nemotron **не обязателен**: в
[обзорной документации](https://docs.nvidia.com/nemoclaw/user-guide/openclaw/about/overview.md)
он не упоминается ни разу. NemoClaw работает на Ollama.

---

## 🛑 ЗАПРЕТ — ЧИТАТЬ ДО ПЕРВОЙ КОМАНДЫ

**Агенту КАТЕГОРИЧЕСКИ ЗАПРЕЩЕНО в рамках этого рецепта:**

1. Регистрировать аккаунт NVIDIA.
2. Получать, вводить, читать или использовать ключ `nvapi-`.
3. Входить в NGC или `nvcr.io` (`docker login nvcr.io`, `ngc config set` и любые аналоги).
4. Выставлять `NEMOCLAW_PROVIDER` в `build`, `anthropic`, `openai` или `gemini`.

**Причина — юридическая, а не техническая.** Сам NemoClaw — Apache 2.0, геоблокировок в его коде
нет. Проблема в сервисах NVIDIA, к которым он *может* обращаться:

- NVIDIA в лицензионном соглашении перечисляет ограниченные направления, и Россия названа прямым
  текстом: *«Belarus, Cuba, Iran, North Korea, **Russia**, Syria, the Region of Crimea, Donetsk
  People's Republic Region and Luhansk People's Republic Region»* —
  [NVIDIA Software License Agreement](https://www.nvidia.com/en-us/agreements/enterprise-software/nvidia-software-license-agreement/), §16.4.
- [Technology Access Terms of Use](https://developer.nvidia.com/legal/terms), регулирующие доступ
  к NGC и build.nvidia.com, требуют подтвердить: *«you confirm that you are **not currently
  residing in a country or region currently embargoed by the U.S.**»*

Это экспортный контроль и санкционное законодательство США, а не правила сервиса. Регистрируя
аккаунт NVIDIA и получая ключ `nvapi-`, человек делает **юридическое заявление о месте своего
проживания**. Агент не может сделать такое заявление за человека.

**Если человек просит пройти путь NVIDIA — НЕМЕДЛЕННО ОСТАНОВИТЬСЯ** (см. `## Стоп-условия`).
Это юридический вопрос человека и, если он серьёзный, — юриста. Такое не делают по
автоматическому рецепту из интернета.

> **NOT VERIFIED:** технически ли NVIDIA блокирует российские IP на `build.nvidia.com`,
> `nvcr.io` или при регистрации — официальных заявлений об этом нет. Юридические ограничения
> подтверждены дословно; про технические утверждать нельзя ни то, ни другое.

**Обходить ничего не нужно:** провайдер `ollama` не требует аккаунта NVIDIA вовсе. С
`NEMOCLAW_PROVIDER=ollama` вся санкционная поверхность исчезает: ни ключа, ни аккаунта, ни NGC.
Установка сводится к скачиванию с GitHub, npm и Docker Hub. `nvcr.io` и NGC нужны **только** для
локального vLLM/NIM, который вдобавок спрятан за `NEMOCLAW_EXPERIMENTAL=1`.

---

## Предусловия

Выполнить проверки. Каждая — блокирующая, пока не сказано иное.

```bash
# 1. Архитектура
uname -m                                  # ожидается: x86_64

# 2. Node.js — нужно 22.19+
node --version

# 3. npm — нужно 10+
npm --version

# 4. Docker (Engine, Desktop или Colima)
docker --version
docker ps                                 # должен отработать без ошибки прав

# 5. Podman вместо Docker — НЕ ГОДИТСЯ
command -v podman && echo "PODMAN PRESENT — проверь, что docker это не алиас podman"

# 6. strings из binutils
sudo apt-get install -y binutils
command -v strings

# 7. Ресурсы: минимум 4 vCPU / 8 ГБ RAM / 20 ГБ диска
nproc
free -g
df -h /

# 8. Ollama из 00-ollama.md жив
ollama --version
```

Требования (официально — [prerequisites](https://docs.nvidia.com/nemoclaw/user-guide/openclaw/get-started/prerequisites.md)):

| Ресурс | Минимум | Рекомендовано |
|---|---|---|
| CPU | 4 vCPU | 4+ |
| RAM | 8 ГБ | 16 ГБ |
| Диск | 20 ГБ | 40 ГБ |

| Зависимость | Версия |
|---|---|
| Node.js | **22.19+** |
| npm | **10+** |
| Docker | Engine, Desktop или Colima |

Важное:

- **Podman не поддерживается.** Onboard выдаёт явную ошибку. Только Docker.
- **Требований к драйверу, CUDA и Python нет вообще** — их нет ни на одной странице документации.
  CLI написан на Node/TypeScript. GPU важен только для локального инференса. Не устанавливай их
  «на всякий случай».
- Установщик **сам поставит Node и Docker**, если их нет. Если `node --version` < 22.19 —
  не чини вручную, дай установщику отработать и перепроверь.

Платформа: из [матрицы платформ](https://docs.nvidia.com/nemoclaw/user-guide/openclaw/reference/platform-support.md)
Linux + Docker имеет статус **Tested, приоритет P0, гоняется в CI**. Дословно: *«Primary tested
path. Ubuntu 24.04 has host-level onboarding validation.»*

> **NOT VERIFIED:** сама DGX OS в матрицу платформ не входит. Она построена на Ubuntu, так что
> `apt-get` работает, но валидация проводилась именно на Ubuntu 24.04.

---

## Переменные

| Переменная | Значение | Зачем |
|---|---|---|
| `NEMOCLAW_INSTALL_TAG` | `v0.0.84` | Пин версии вместо подвижного тега `lkg`. **Обязательно.** |
| `NEMOCLAW_PROVIDER` | `ollama` | Единственное допустимое значение. См. запрет выше. |
| `NEMOCLAW_SANDBOX_NAME` | `my-claw` | Имя песочницы. Используется во всех последующих командах. |
| `NEMOCLAW_NON_INTERACTIVE` | `1` | Установка без вопросов. |
| `NEMOCLAW_ACCEPT_THIRD_PARTY_SOFTWARE` | `1` | Согласие на стороннее ПО. |
| `NEMOCLAW_NO_EXPRESS` | `1` | **Только если DMI сообщает DGX Station.** См. Шаг 2. |
| `NEMOCLAW_REQUIRE_CAP_DROP` | `1` | Строгий режим сброса привилегий. **Ставить всегда.** См. Шаг 2. |

**Правило размещения переменных — нарушение ломает установку молча:**

> ⚠️ **Переменные — справа от `|`, рядом с `bash`. Не перед `curl`.** Прямое предупреждение из
> [quickstart](https://docs.nvidia.com/nemoclaw/user-guide/openclaw/get-started/quickstart.md):
> *«Do not place `NEMOCLAW_ACCEPT_THIRD_PARTY_SOFTWARE=1` before `curl`, because the installer
> process cannot read it there.»*

Запрещённые значения `NEMOCLAW_PROVIDER` —
[choose-inference-provider](https://docs.nvidia.com/nemoclaw/user-guide/openclaw/inference/learn-and-choose/choose-inference-provider.md):

| Провайдер | Что нужно | Годится? |
|---|---|---|
| `build` | ключ `nvapi-` | ❌ юридический вопрос → **СТОП** |
| `anthropic` / `openai` | ключ | ❌ страна не поддерживается → **СТОП** |
| `gemini` | ключ | ❌ то же → **СТОП** |
| `custom` | свой OpenAI-совместимый URL | ⚠️ можно, но не в этом рецепте |
| **`ollama`** | **ничего** | ✅ **используй это** |

---

## Шаги

### Шаг 1. Зафиксировать факты об установщике (без выполнения)

Знать до запуска, объяснить человеку при вопросе:

1. `https://www.nvidia.com/nemoclaw.sh` — **не файл NVIDIA**. Это 302-редирект на
   `raw.githubusercontent.com/NVIDIA/NemoClaw/refs/heads/main/install.sh`.
2. Этот скрипт — тонкий загрузчик: клонирует тег **`lkg`** и запускает `scripts/install.sh` оттуда.
3. **`lkg` — подвижный тег.** Он переезжает. Поэтому пин `NEMOCLAW_INSTALL_TAG=v0.0.84`.
4. **Полезная нагрузка НЕ проверяется по хэшу.** Функция `verify_downloaded_script` вызывается
   без ожидаемой суммы — проверяется лишь, что файл непустой и с шебангом. Доверие держится
   целиком на HTTPS + GitHub + плавающем теге NVIDIA.

Проверить, что тег `v0.0.84` существует:

```bash
git ls-remote --tags https://github.com/NVIDIA/NemoClaw.git | grep -F 'v0.0.84'
```

- **Ожидаемый результат:** непустая строка с хэшем и `refs/tags/v0.0.84`.
- **Если не так:** `v0.0.84` — последний опубликованный тег на момент написания. Если тега нет
  или `git ls-remote` не отвечает — **не подставляй `lkg` и не выбирай тег сам**. Останови
  установку и покажи человеку полный вывод `git ls-remote --tags`.

### Шаг 2. Определить платформу по DMI и собрать флаги безопасности

Установщик определяет платформу по DMI-строке материнской платы и возвращает `spark`, `station`,
`jetson` или общий `linux`.

| Платформа | Статус |
|---|---|
| DGX Spark (arm64) | **Tested**, в CI |
| DGX Station (arm64) | **Deferred**, не в CI, «not validated end-to-end on physical hardware» |
| Обычный x86_64 сервер | определяется как `linux` → **P0 Tested** |

Обычный DGX-сервер с A100/H100 попадает в класс `linux` — самый обкатанный путь.

⚠️ **Ловушка DGX Station A100.** Это машина **x86_64**, но её DMI-строка совпадёт с шаблоном
`/DGX[_\s-]+Station/i`. Тогда установщик решит, что он на arm64-Station, предложит «экспресс-путь»
и потащит рецепт `nemotron-3-ultra-550b-a55b` размером примерно **352 ГБ**, чей образ на Station
резолвится в **arm64-манифест**. Итог: огромная закачка, которая на x86_64 не заработает.

Проверить DMI (чтение материнской платы; шаблон `/DGX[_\s-]+Station/i` — из исходников установщика):

```bash
cat /sys/class/dmi/id/product_name /sys/class/dmi/id/board_name 2>/dev/null
```

- **Если вывод совпадает с `DGX Station` (регистр не важен, разделитель — пробел, `_` или `-`):**
  обязательно `export NEMOCLAW_NO_EXPRESS=1`.
- **Если не совпадает:** переменная не нужна, но и не вредит.
- **Если файлы DMI не читаются:** ставь `NEMOCLAW_NO_EXPRESS=1` — хуже от неё не будет.

> Эта ловушка **выведена из исходного кода** `src/lib/inference/nim.ts`, **а не из документации
> NVIDIA**. Официального подтверждения нет. Сама переменная `NEMOCLAW_NO_EXPRESS` документирована.

Строгий режим сброса привилегий — **ставить всегда**. Открытый issue #3280: проверка сброса
привилегий по умолчанию **предупреждает, но не блокирует**, чтобы хосты без `CAP_SETPCAP` могли
загрузиться. Следствие, дословно: *«dangerous caps can remain in the bounding set on some hosts»*.
Песочница нужна ради изоляции — без этой переменной затея теряет смысл.

```bash
export NEMOCLAW_REQUIRE_CAP_DROP=1
export NEMOCLAW_NO_EXPRESS=1        # только по результату проверки DMI выше
```

- **Ожидаемый результат:** `echo "$NEMOCLAW_REQUIRE_CAP_DROP"` печатает `1`.
- **Если не так:** не продолжать. Источник не уточняет, нужна ли `NEMOCLAW_REQUIRE_CAP_DROP`
  только при установке или при каждом запуске, — держи её в окружении на всё время работы
  с песочницей.

### Шаг 3. Установка с пином версии и провайдером ollama

Одна команда. Переменные — **справа от `|`**.

```bash
curl -fsSL https://www.nvidia.com/nemoclaw.sh | \
  NEMOCLAW_INSTALL_TAG=v0.0.84 \
  NEMOCLAW_NON_INTERACTIVE=1 \
  NEMOCLAW_ACCEPT_THIRD_PARTY_SOFTWARE=1 \
  NEMOCLAW_PROVIDER=ollama \
  NEMOCLAW_SANDBOX_NAME=my-claw \
  bash
```

- **Ожидаемый результат:** установщик отрабатывает до конца; `nemoclaw --version` печатает версию.
- **Если установщик просит добавиться в группу docker:** он завершится с этой просьбой. Тогда:

  ```bash
  newgrp docker
  curl -fsSL https://www.nvidia.com/nemoclaw.sh | NEMOCLAW_INSTALL_TAG=v0.0.84 bash
  ```

  После `newgrp` переменные окружения из Шага 2 нужно выставить заново.
- **Если установка обрывается:**

  ```bash
  nemoclaw onboard --resume    # продолжить
  nemoclaw onboard --fresh     # начать заново
  ```

- **Если не скачивается `raw.githubusercontent.com`:** ⚠️ из России установка, скорее всего,
  споткнётся на первом же шаге — `raw.githubusercontent.com` регулярно недоступен. Это блокировка
  со стороны российских провайдеров, а не NVIDIA, — как и с `ollama pull`. Прокси здесь уместен.

  > **NOT VERIFIED:** официальной документации по работе NemoClaw за прокси **нет**. Готовься
  > экспериментировать. Не выдавай результат эксперимента за документированное поведение.

  Смежный факт: установка без интернета не поддерживается — в матрице платформ air-gapped имеет
  статус **Unsupported**. Открытый [issue #2218](https://github.com/NVIDIA/NemoClaw/issues/2218)
  называется *«epic: production deployment improvements (air-gapped support, China network
  guidance…)»* и признаёт, что сети с блокировками не документированы и не поддержаны. Россия —
  та же категория проблемы, решения NVIDIA пока не предложила.

- **Если установщик предлагает экспресс-путь или начинает тянуть ~352 ГБ
  (`nemotron-3-ultra-550b-a55b`):** прервать немедленно, вернуться к Шагу 2 и выставить
  `NEMOCLAW_NO_EXPRESS=1`.
- **Если установщик запрашивает ключ `nvapi-`, аккаунт NVIDIA или логин в NGC:** **СТОП.**
  См. `## Стоп-условия`. Проверь, что `NEMOCLAW_PROVIDER=ollama` попал справа от `|`.

### Шаг 4. Проверить статус песочницы

```bash
nemoclaw my-claw status
docker ps
```

- **Ожидаемый результат:** `status` показывает работающую песочницу; `docker ps` показывает
  контейнеры OpenShell.
- **Если не так:** `nemoclaw onboard --resume`. Если не помогает — `nemoclaw onboard --fresh`.

### Шаг 5. Дашборд — получить URL, не раскрывая токен

Дашборд слушает `127.0.0.1:18789`.

```bash
ss -ltn | grep -F 18789
```

- **Ожидаемый результат:** порт `127.0.0.1:18789` слушается.

> 🔒 **URL дашборда — это пароль.** Дословно из документации: *«The complete dashboard URL
> contains a gateway token fragment that authenticates the browser session. Treat an
> authenticated dashboard URL as a password.»*
>
> **Правила для агента:** НЕ выполнять `nemoclaw my-claw dashboard-url` с выводом в лог,
> транскрипт, файл отчёта, сообщение или историю команд. НЕ пересылать URL. Не публиковать.
> Команду для получения URL **отдать человеку**, чтобы он выполнил её сам в своей сессии:

```bash
nemoclaw my-claw dashboard-url --quiet
```

Туннель до дашборда человек поднимает со своей машины:

```bash
ssh -L 18789:127.0.0.1:18789 пользователь@адрес-dgx
```

Дальше человек открывает полученный URL в браузере на своей машине.

### Шаг 6. Подключение агента

```bash
nemoclaw my-claw connect
```

- **Ожидаемый результат:** подключение проходит.

`openclaw tui` — **интерактивный TUI**. Агент его не запускает в автономном режиме: он не
завершится сам и заблокирует сессию. Оставь человеку:

```bash
openclaw tui
```

Проверка, что инференс реально идёт через Ollama, — при запросе в `nvidia-smi` видна нагрузка:

```bash
nvidia-smi
```

---

## Стоп-условия

**Остановиться и передать вопрос человеку. Не искать обход. Не продолжать «частично».**

1. **Человек просит путь NVIDIA** — зарегистрировать аккаунт NVIDIA, получить ключ `nvapi-`,
   войти в NGC/`nvcr.io`, или выставить `NEMOCLAW_PROVIDER` в `build` / `anthropic` / `openai` /
   `gemini`.

   **Ответ человеку, по смыслу:** это не техническая задача, а юридическая. NVIDIA в лицензионном
   соглашении называет Россию среди ограниченных направлений
   ([NVIDIA Software License Agreement](https://www.nvidia.com/en-us/agreements/enterprise-software/nvidia-software-license-agreement/), §16.4),
   а [Technology Access ToU](https://developer.nvidia.com/legal/terms) требуют подтвердить, что
   ты не проживаешь в стране под эмбарго США. Это экспортный контроль и санкционное
   законодательство США. Получая ключ `nvapi-`, ты делаешь юридическое заявление о месте своего
   проживания — за тебя это не может сделать ни агент, ни инструкция. Обсуди со взрослыми и, если
   вопрос серьёзный, с юристом. **Такое не проходят по автоматическому рецепту.** Рабочая
   альтернатива без всякой юридической поверхности — `NEMOCLAW_PROVIDER=ollama`, она уже в этом
   рецепте.

2. **Установщик сам требует ключ `nvapi-`, аккаунт NVIDIA или логин в NGC.** Не вводить ничего.
   Проверить, что `NEMOCLAW_PROVIDER=ollama` стоит справа от `|`. Если требование остаётся —
   остановиться и показать человеку вывод.

3. **Тег `v0.0.84` не найден** через `git ls-remote --tags`. Не подставлять `lkg`, не выбирать
   тег самостоятельно.

4. **Установщик тянет ~352 ГБ** (`nemotron-3-ultra-550b-a55b`) или предлагает экспресс-путь.
   Прервать, вернуться к Шагу 2.

5. **Единственная найденная замена Docker — Podman.** Podman не поддерживается, onboard выдаёт
   явную ошибку.

6. **Требуется прокси, чтобы дотянуться до `raw.githubusercontent.com`.** Настройка прокси не
   описана в источнике и не документирована NVIDIA (**NOT VERIFIED**). Спросить человека,
   а не изобретать конфигурацию молча.

7. **Появилась необходимость выполнить `nemoclaw my-claw dashboard-url` с сохранением вывода.**
   URL содержит токен аутентификации. Передать команду человеку.

---

## Критерий готовности

Проверяемо машинно. Все команды должны отработать:

```bash
nemoclaw --version                        # печатает версию
nemoclaw my-claw status                   # показывает работающую песочницу
docker ps                                 # видны контейнеры OpenShell
ss -ltn | grep -F 18789                   # дашборд слушает 127.0.0.1:18789
echo "$NEMOCLAW_REQUIRE_CAP_DROP"         # печатает 1
nvidia-smi                                # при запросе видна нагрузка → инференс идёт через Ollama
```

Дополнительно — **проверяет человек, не агент**:

- [ ] дашборд открывается через SSH-туннель (`ssh -L 18789:127.0.0.1:18789 пользователь@адрес-dgx`)
- [ ] `openclaw tui` подключается и отвечает

Инвариант, который должен остаться истинным по завершении:

- [ ] аккаунт NVIDIA не создан
- [ ] ключ `nvapi-` не получен и нигде не фигурирует
- [ ] логина в NGC / `nvcr.io` не было
- [ ] `NEMOCLAW_PROVIDER` = `ollama`
- [ ] URL дашборда не попал ни в один лог, файл или сообщение

---

## Что помнить про зрелость проекта

- **Это alpha, и NVIDIA этого не скрывает.** Версия в `package.json` — `0.1.0`. Из
  [README](https://github.com/NVIDIA/NemoClaw): *«NemoClaw is an alpha project»*. Из
  [enterprise-readiness](https://docs.nvidia.com/nemoclaw/user-guide/openclaw/reference/enterprise-readiness.md):
  *«**NemoClaw is not a hardened, multi-tenant enterprise control plane.** It is in active
  development, and **interfaces can change between releases**.»* Флаги и переменные из этого
  рецепта проверены для `v0.0.84`. При другом теге — перепроверяй, не предполагай.
- **Документация местами врёт ссылками.** Страницы `quickstart.html` и `about/how-it-works`,
  на которые ведёт README, отдают **404**. Живой индекс —
  [llms.txt](https://docs.nvidia.com/nemoclaw/llms.txt). Приём из официальной документации:
  **допиши `.md` к любому адресу доков** — получишь чистый markdown.
- **Зачем эта установка вообще.** У OpenClaw песочница по умолчанию выключена, а он выполняет
  произвольные shell-команды. NemoClaw существует ровно для того, чтобы эту дыру закрыть. Если
  OpenClaw ставится ради безопасности — ставить его отсюда, а не из
  [06-openclaw.md](../for-human/06-openclaw.md).
