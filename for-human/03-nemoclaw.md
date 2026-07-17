# 03. NemoClaw + OpenShell — песочница NVIDIA для агентов

Требуется: выполненная инструкция [00-ollama.md](00-ollama.md).

## Что это на самом деле

Распространённое заблуждение: NemoClaw — это агент или модель. **Нет.** Дословно из
[README](https://github.com/NVIDIA/NemoClaw):

> NVIDIA NemoClaw is an open source reference stack for running always-on AI agents
> more safely inside NVIDIA OpenShell sandboxes.

Это **обёртка**, которая запускает чужого агента в песочнице:

```
NemoClaw  ──управляет──>  OpenShell  ──изолирует и запускает──>  OpenClaw / Hermes
```

| Проект | Роль | Чей |
|---|---|---|
| **NemoClaw** | CLI + чертёж развёртывания | NVIDIA |
| **OpenShell** | песочница: сеть, ФС, процессы, маршрутизация инференса | NVIDIA |
| **OpenClaw** | агент внутри. **По умолчанию** | сторонний |
| **Hermes** | альтернативный агент (`nemohermes`) | Nous Research |
| **Nemotron** | модели NVIDIA. **Не обязательны** | NVIDIA |

Про Nemotron: маркетинг [на сайте](https://www.nvidia.com/en-us/ai/nemoclaw/) подаёт его как
центр стека, но в [обзорной документации](https://docs.nvidia.com/nemoclaw/user-guide/openclaw/about/overview.md)
Nemotron **не упоминается ни разу**. NemoClaw прекрасно работает на Ollama.

**Зачем это тебе.** У OpenClaw песочница по умолчанию выключена, а он выполняет произвольные
shell-команды. NemoClaw существует ровно для того, чтобы эту дыру закрыть. Если ставишь
OpenClaw ради безопасности — ставь его отсюда, а не из [06-openclaw.md](06-openclaw.md).

---

## ⚠️ Юридический вопрос — прочитай до установки

**Сам NemoClaw — Apache 2.0, никаких ограничений.** В его коде нет ни одной геоблокировки.
Проблема не в нём, а в сервисах NVIDIA, к которым он *может* обращаться.

NVIDIA в лицензионном соглашении перечисляет ограниченные направления, и **Россия названа
прямым текстом**:

> Belarus, Cuba, Iran, North Korea, **Russia**, Syria, the Region of Crimea, Donetsk
> People's Republic Region and Luhansk People's Republic Region

— [NVIDIA Software License Agreement](https://www.nvidia.com/en-us/agreements/enterprise-software/nvidia-software-license-agreement/), §16.4

А [Technology Access Terms of Use](https://developer.nvidia.com/legal/terms), которые
регулируют доступ к NGC и build.nvidia.com, требуют подтвердить:

> you confirm that you are **not currently residing in a country or region currently
> embargoed by the U.S.**

Это **экспортный контроль и санкционное законодательство США**, а не правила сервиса.
Регистрируя аккаунт NVIDIA и получая ключ `nvapi-`, ты делаешь юридическое заявление
о месте своего проживания.

**Поэтому в этой инструкции нет и не будет шагов по регистрации аккаунта NVIDIA, получению
ключа `nvapi-` и входу в NGC.** Если тебе это нужно — обсуди со взрослыми и, если вопрос
серьёзный, с юристом. Не проходи такое по инструкции из интернета.

> **NOT VERIFIED:** технически ли NVIDIA блокирует российские IP на `build.nvidia.com`,
> `nvcr.io` или при регистрации — официальных заявлений об этом нет. Юридические
> ограничения подтверждены дословно; про технические утверждать нельзя ни то, ни другое.

**Хорошая новость: обходить ничего не нужно.** Есть провайдер, которому NVIDIA-аккаунт
не требуется вовсе — см. Шаг 3.

---

## Шаг 0. Проверить требования

Официально — [prerequisites](https://docs.nvidia.com/nemoclaw/user-guide/openclaw/get-started/prerequisites.md):

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

Важные подробности, которых нет в популярных обзорах:

- **Podman не поддерживается.** Onboard выдаёт явную ошибку. Только Docker.
- **Требований к драйверу, CUDA и Python нет вообще** — их нет ни на одной странице
  документации. CLI написан на Node/TypeScript. GPU важен только для локального инференса.
- Нужен `strings` из пакета `binutils`.
- Установщик **сам поставит Node и Docker**, если их нет.

```bash
node --version    # нужно 22.19+
docker --version
sudo apt-get install -y binutils
```

**Твоя платформа — лучшая из поддерживаемых.** Из [матрицы платформ](https://docs.nvidia.com/nemoclaw/user-guide/openclaw/reference/platform-support.md):
Linux + Docker имеет статус **Tested, приоритет P0, гоняется в CI**. Дословно:
*«Primary tested path. Ubuntu 24.04 has host-level onboarding validation.»*

> **NOT VERIFIED:** сама DGX OS в матрицу платформ не входит. Она построена на Ubuntu,
> так что `apt-get` работает, но валидация проводилась именно на Ubuntu 24.04.

---

## Шаг 1. Установка — с пином версии

### Что происходит на самом деле

Это тот случай, ради которого стоит читать исходники, а не рекламу. Официальная команда:

```bash
curl -fsSL https://www.nvidia.com/nemoclaw.sh | bash
```

Что за ней стоит:

1. `https://www.nvidia.com/nemoclaw.sh` — **не файл NVIDIA**. Это 302-редирект на
   `raw.githubusercontent.com/NVIDIA/NemoClaw/refs/heads/main/install.sh`.
2. Этот скрипт — тонкий загрузчик. Он клонирует тег **`lkg`** и запускает `scripts/install.sh` оттуда.
3. **`lkg` — подвижный тег.** Он переезжает.
4. **Полезная нагрузка не проверяется по хэшу.** Функция `verify_downloaded_script`
   вызывается без ожидаемой суммы — проверяется лишь, что файл непустой и с шебангом.

То есть доверие держится целиком на HTTPS + GitHub + плавающем теге NVIDIA. Для paranoid-уровня
этого мало.

### Как ставить правильно

Пин на реальный релиз вместо плавающего `lkg`:

```bash
curl -fsSL https://www.nvidia.com/nemoclaw.sh | NEMOCLAW_INSTALL_TAG=v0.0.84 bash
```

`v0.0.84` — последний опубликованный тег на момент написания. Актуальный список:

```bash
git ls-remote --tags https://github.com/NVIDIA/NemoClaw.git
```

### Если добавили в группу docker

Установщик завершится и попросит:

```bash
newgrp docker
curl -fsSL https://www.nvidia.com/nemoclaw.sh | NEMOCLAW_INSTALL_TAG=v0.0.84 bash
```

### Если установка обрывается

```bash
nemoclaw onboard --resume    # продолжить
nemoclaw onboard --fresh     # начать заново
```

⚠️ **Из России установка, скорее всего, споткнётся на первом же шаге:**
`raw.githubusercontent.com` регулярно недоступен. Это блокировка со стороны российских
провайдеров, а не NVIDIA, — как и с `ollama pull`. Прокси здесь уместен.

Официальной документации по работе NemoClaw за прокси **нет** — **NOT VERIFIED**, готовься
экспериментировать.

---

## Шаг 2. Определить, за кого установщик тебя примет

Установщик определяет платформу **по DMI-строке материнской платы** и возвращает `spark`,
`station`, `jetson` или общий `linux`. Посмотри, что скажет твоя:

```bash
uname -m
cat /sys/class/dmi/id/product_name /sys/class/dmi/id/sys_vendor
```

**Настоящие «DGX» в документации — это arm64:**

| Платформа | Статус |
|---|---|
| DGX Spark (arm64) | **Tested**, в CI |
| DGX Station (arm64) | **Deferred**, не в CI, «not validated end-to-end on physical hardware» |
| Обычный x86_64 сервер | определяется как `linux` → **P0 Tested** |

### Случай 1: DGX Spark под чужим брендом (Dell, HP, Lenovo, ASUS)

Если `uname -m` даёт `aarch64`, а DMI — что-то вроде `Dell Pro Max with GB10 FCM1253` /
`Dell Inc.`, то ты на DGX Spark, **но установщик об этом не узнает**: в DMI нет ни слова
«DGX», ни «Spark». Тебя определят как обычный `linux`.

Практических следствий два, и оба скорее хорошие:

- **`NEMOCLAW_NO_EXPRESS=1` тебе не нужен.** Ловушка ниже срабатывает по шаблону
  `/DGX[_\s-]+Station/i` — строка Dell под него не подходит, «экспресс-путь» не предложат.
- Класс `linux` — это **P0 Tested**, самый обкатанный путь. Ветка `spark` формально
  «Tested в CI», но в неё ты не попадёшь.

> **NOT VERIFIED:** как именно класс `linux` выбирает архитектуру образов — по `uname -m`
> или по классу платформы. Если по классу, arm64-машина в классе `linux` может получить
> x86-образы. В документации NVIDIA это не описано. **Первый `nemoclaw onboard` запускай
> при человеке** и смотри, что именно качается: если пошёл многогигабайтный образ,
> проверь его архитектуру, прежде чем ждать полчаса.

### Случай 2: DGX Station A100 — вот здесь ловушка

⚠️ **DGX Station A100 — машина x86_64**, но её DMI-строка совпадёт с шаблоном
`/DGX[_\s-]+Station/i`. Тогда установщик решит, что ты на arm64-Station, предложит
«экспресс-путь» и потащит рецепт `nemotron-3-ultra-550b-a55b` размером примерно
**352 ГБ**, чей образ на Station резолвится в **arm64-манифест**. Огромная закачка,
которая на x86_64 не заработает.

**Защита — только для этого случая:**

```bash
export NEMOCLAW_NO_EXPRESS=1
```

*(Эту ловушку я вывел из исходного кода `src/lib/inference/nim.ts`, а не из документации NVIDIA.
Официального подтверждения нет — но переменная `NEMOCLAW_NO_EXPRESS` документирована, и хуже
от неё не будет.)*

**На DGX Spark и на обычном x86-сервере эта переменная не нужна** — ставить её «на всякий
случай» смысла нет: она отключает путь, который тебе и так не предложат.

---

## Шаг 3. Провайдер инференса — только Ollama

NemoClaw поддерживает несколько провайдеров —
[choose-inference-provider](https://docs.nvidia.com/nemoclaw/user-guide/openclaw/inference/learn-and-choose/choose-inference-provider.md):

| Провайдер | Что нужно | Годится тебе? |
|---|---|---|
| `build` | ключ `nvapi-` | ❌ юридический вопрос выше |
| `anthropic` | ключ | ❌ [страна не поддерживается](https://www.anthropic.com/supported-countries) |
| `openai` | ключ | ⚠️ см. оговорку ниже |
| `gemini` | ключ | ⚠️ см. оговорку ниже |
| `custom` | свой OpenAI-совместимый URL | ⚠️ можно |
| **`ollama`** | **ничего** | ✅ **это твой вариант** |

> **NOT VERIFIED — исправление.** Раньше `openai` и `gemini` стояли здесь в одной строке
> с `anthropic` и помечались «страна не поддерживается». Для Anthropic это
> [подтверждено ссылкой](https://www.anthropic.com/supported-countries); **для OpenAI и
> Google я источник не проверял** и приписал им чужое ограничение по аналогии. Убрал.
>
> На выбор это не влияет: `ollama` выигрывает у всех троих по другой причине — **ему не
> нужны ни ключ, ни аккаунт, ни чьё-либо разрешение**, а модель работает на твоём железе.
> Это довод сильнее любых страновых списков, и он не зависит от их содержания.

```bash
curl -fsSL https://www.nvidia.com/nemoclaw.sh | \
  NEMOCLAW_INSTALL_TAG=v0.0.84 \
  NEMOCLAW_NON_INTERACTIVE=1 \
  NEMOCLAW_ACCEPT_THIRD_PARTY_SOFTWARE=1 \
  NEMOCLAW_PROVIDER=ollama \
  NEMOCLAW_REQUIRE_CAP_DROP=1 \
  NEMOCLAW_SANDBOX_NAME=my-claw \
  bash
```

> ⚠️ **Переменные — справа от `|`, рядом с `bash`.** Не перед `curl`. Это прямое
> предупреждение из [quickstart](https://docs.nvidia.com/nemoclaw/user-guide/openclaw/get-started/quickstart.md):
> *«Do not place `NEMOCLAW_ACCEPT_THIRD_PARTY_SOFTWARE=1` before `curl`, because the
> installer process cannot read it there.»*

### 🔒 Про `NEMOCLAW_REQUIRE_CAP_DROP=1` — не выбрасывай эту строку

Ты ставишь NemoClaw **ради изоляции**. Без этой переменной изоляция может оказаться
дырявой, и ты об этом не узнаешь.

Открытый [issue #3280](https://github.com/NVIDIA/NemoClaw/issues/3280): проверка сброса
привилегий по умолчанию **предупреждает, но не блокирует** — чтобы хосты без `CAP_SETPCAP`
могли загрузиться. Следствие дословно: *«dangerous caps can remain in the bounding set on
some hosts»*.

То есть песочница поднимется, всё будет выглядеть работающим, а часть опасных привилегий
останется. Переменная превращает предупреждение в отказ: либо изоляция настоящая, либо
установка не проходит.

**Держи её в окружении всё время работы с песочницей**, а не только при установке —
источник не уточняет, нужна ли она при каждом запуске:

```bash
export NEMOCLAW_REQUIRE_CAP_DROP=1
```

С `NEMOCLAW_PROVIDER=ollama` вся санкционная поверхность исчезает: ни ключа, ни аккаунта,
ни NGC. Установка сводится к скачиванию с GitHub, npm и Docker Hub.

`nvcr.io` и NGC нужны **только** для локального vLLM/NIM — тебе они не нужны.
Локальный NIM вдобавок спрятан за `NEMOCLAW_EXPERIMENTAL=1`.

---

## Шаг 4. Проверить и подключиться

```bash
nemoclaw my-claw status
nemoclaw my-claw dashboard-url --quiet
nemoclaw my-claw connect
openclaw tui
```

Дашборд слушает `127.0.0.1:18789`. По SSH:

```bash
ssh -L 18789:127.0.0.1:18789 пользователь@адрес-dgx
```

Дальше открой полученный URL в браузере на своей машине.

> 🔒 **URL дашборда — это пароль.** Дословно из документации:
> *«The complete dashboard URL contains a gateway token fragment that authenticates the
> browser session. Treat an authenticated dashboard URL as a password.»*
> Не пересылай его в мессенджерах и не публикуй.

---

## Риски — честно

**1. Это alpha, и NVIDIA этого не скрывает.** Версия в `package.json` — `0.1.0`.
Из [README](https://github.com/NVIDIA/NemoClaw): *«NemoClaw is an alpha project»*.
Из [enterprise-readiness](https://docs.nvidia.com/nemoclaw/user-guide/openclaw/reference/enterprise-readiness.md):

> **NemoClaw is not a hardened, multi-tenant enterprise control plane.**
> It is in active development, and **interfaces can change between releases**.

**2. У песочницы есть незакрытая дыра.** Открытый issue #3280: проверка сброса привилегий
по умолчанию **предупреждает, но не блокирует** — чтобы хосты без `CAP_SETPCAP` могли
загрузиться. Следствие, дословно: *«dangerous caps can remain in the bounding set on some hosts»*.

Лечится переменной `NEMOCLAW_REQUIRE_CAP_DROP=1` — она уже стоит в команде установки
в **Шаге 3**, разбор там же. Если ставил раньше и без неё — переустанови с ней.

**3. Установка без интернета не поддерживается.** Из матрицы платформ: air-gapped —
**Unsupported**. Открытый [issue #2218](https://github.com/NVIDIA/NemoClaw/issues/2218)
называется *«epic: production deployment improvements (air-gapped support, China network
guidance…)»* и признаёт, что сети с блокировками не документированы и не поддержаны.
Россия — та же категория проблемы, и решения NVIDIA пока не предложила.

**4. Документация местами врёт ссылками.** Страницы `quickstart.html` и `about/how-it-works`,
на которые ведёт README, отдают **404**. Живой индекс — [llms.txt](https://docs.nvidia.com/nemoclaw/llms.txt).
Полезный приём из официальной документации: **допиши `.md` к любому адресу доков** — получишь
чистый markdown.

---

## Готово, если

- [ ] `nemoclaw --version` печатает версию
- [ ] **`echo $NEMOCLAW_REQUIRE_CAP_DROP` печатает `1`** — иначе изоляция может быть дырявой (Шаг 3)
- [ ] `nemoclaw my-claw status` показывает работающую песочницу
- [ ] `docker ps` показывает контейнеры OpenShell
- [ ] дашборд открывается через SSH-туннель
- [ ] `openclaw tui` подключается и отвечает
- [ ] в `nvidia-smi` видна нагрузка при запросе (значит, инференс идёт через Ollama)
