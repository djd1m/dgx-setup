# 06. OpenClaw — рецепт для AI-кодера

Цель: установить OpenClaw на x86_64 Ubuntu/DGX-OS, направить его на локальную Ollama **без `/v1`**, привести безопасность в осознанное состояние и убедиться, что агент **выполняет** инструменты, а не печатает их вызовы текстом.

Репозиторий: [github.com/openclaw/openclaw](https://github.com/openclaw/openclaw). Документация: [docs.openclaw.ai](https://docs.openclaw.ai/).

Дословно из [README](https://github.com/openclaw/openclaw):

> a *personal AI assistant* you run on your own devices. It answers you on the channels
> you already use.

29+ каналов связи (Telegram, WhatsApp, Slack, Discord, Signal, Matrix…), долговременная память, управление браузером, доступ к файлам, выполнение команд, магазин плагинов. Автор — Peter Steinberger, 346k+ звёзд.

---

## 🛑 Прочитать до первой команды: возможно, ставить надо не это

**У OpenClaw песочница по умолчанию выключена**, а он выполняет произвольные shell-команды. [NemoClaw](../for-human/03-nemoclaw.md) существует ровно для того, чтобы запускать OpenClaw **внутри изолированной песочницы OpenShell**.

| Что ставить | Когда |
|---|---|
| **[03-nemoclaw.md](../for-human/03-nemoclaw.md)** | нужен OpenClaw + изоляция. **Рекомендуется** |
| **Эта инструкция** | нужен OpenClaw сам по себе, изоляцию берёшь на себя |

Если цель установки — изоляция, или если задача сформулирована без явного «изоляцию беру на себя»: остановиться, предложить человеку 03-nemoclaw.md, дальше не идти. Если сомневаешься — иди в 03.

---

## Предусловия

Выполнена инструкция [00-ollama.md](../for-human/00-ollama.md).

```bash
ollama list
```

Ожидаемый результат: таблица со скачанными моделями; целевая модель присутствует в колонке `NAME`.
Если не так, то: остановиться, вернуться к 00-ollama.md. Модель, которой нет в `ollama list`, использовать нельзя.

```bash
node --version
```

Ожидаемый результат: **24.15+ (рекомендуется), либо 22.22.3+, либо 25.9+** — [install](https://docs.openclaw.ai/install).
Если не так, то: не чинить руками. Шаг 1 через `install.sh` ставит Node сам, если его нет. Если Node есть, но версия ниже — обновить Node до 24.15+ и перепроверить.

Docker **не обязателен**. Дословно: *«Docker is **optional**. Use it for an isolated, throwaway gateway environment»* — [docker](https://docs.openclaw.ai/install/docker).

---

## Переменные

| Переменная / значение | Значение | Смысл |
|---|---|---|
| Адрес Ollama для OpenClaw | `http://127.0.0.1:11434` | 🔥 **БЕЗ `/v1`**. См. Шаг 3 |
| `OLLAMA_API_KEY` | `ollama-local` | нужна только чтобы **включить провайдера**; значение произвольное |
| Модель | `ollama/qwen3.6:27b` | префикс `ollama/` обязателен; имя после префикса должно совпадать с `ollama list` посимвольно |
| Главный конфиг | `~/.openclaw/openclaw.json` | формат **JSON5**, не обычный JSON |
| Рабочая папка | `~/.openclaw/workspace` | файлы личности агента |
| Порт шлюза | `18789` | шлюз слушает его |

---

## Шаги

### Шаг 1. Установка

```bash
curl -fsSL https://openclaw.ai/install.sh | bash
```

Что делает этот скрипт (файл на 111.7 КБ, прочитан): ставит Node, если его нет (через apt/pacman/dnf/yum/apk или NodeSource), проверяет версию SQLite в Node, глобально устанавливает npm-пакет **`openclaw`**, чинит права npm на Linux. Для системных пакетов нужен sudo; если зависимости уже стоят, повышение прав пропускается.

Ожидаемый результат: скрипт отработал без ошибки.

Если не так, то — ветка npm:

```bash
npm install -g openclaw@latest
openclaw onboard --install-daemon
```

Если не отработали обе ветки: остановиться, спросить человека. См. «Стоп-условия».

### Шаг 2. Проверить установку

```bash
openclaw --version
openclaw doctor
openclaw gateway status
```

Ожидаемый результат: `--version` печатает версию; `doctor` не ругается; `gateway status` — работает. Шлюз слушает порт **18789**.
Если не так, то: вернуться к шагу 1 и выполнить ветку npm. `doctor` перепроверить ещё раз после Шага 5 — там он ловит отдельную ошибку про namespaces.

### Шаг 3. 🔥 Подключить Ollama — адрес БЕЗ `/v1`

**Это главная ловушка всей инструкции.** Дословное предупреждение из [providers/ollama](https://docs.openclaw.ai/providers/ollama):

> **Do not use the `/v1` OpenAI-compatible URL** (`http://host:11434/v1`).
> It breaks tool calling and models can emit raw tool-call JSON as plain text.

| Программа | Адрес Ollama |
|---|---|
| **OpenClaw** | `http://127.0.0.1:11434` ← **без `/v1`** |
| Hermes, Ouroboros | `http://localhost:11434/v1` ← **с `/v1`** |
| Claude Code | `http://localhost:11434` |

⚠️ **Не сопоставлять по шаблону с соседними инструкциями этого репозитория.** Hermes (04) и Ouroboros (05) используют `/v1` — и это правильно для них. Для OpenClaw `/v1` — ошибка. Скопируешь адрес из соседнего файла — сломаешь вызов инструментов.

Перепутаешь — агент начнёт печатать JSON вызовов инструментов текстом вместо их выполнения. Симптом легко принять за «тупую модель».

Задать модель. Либо правкой `~/.openclaw/openclaw.json` (формат **JSON5**):

```json5
{
  agents: {
    defaults: {
      model: {
        primary: "ollama/qwen3.6:27b"
      }
    }
  }
}
```

Либо командой:

```bash
export OLLAMA_API_KEY="ollama-local"
openclaw models set ollama/qwen3.6:27b
openclaw models status
```

Переменная `OLLAMA_API_KEY` нужна, чтобы включить провайдера — значение произвольное.

Ожидаемый результат: `openclaw models status` показывает `ollama/...`.

Проверка адреса на `/v1` — обязательна, статически:

```bash
grep -rn "11434/v1" ~/.openclaw/ ; env | grep -i "11434/v1"
```

Ожидаемый результат: **пусто из обеих команд**. Ни одного вхождения `11434/v1`.
Если не так, то: убрать `/v1` из найденного места, оставить `http://127.0.0.1:11434`, перепроверить. Это не косметика — на этом ломается вызов инструментов.

### Шаг 4. Размер модели — не экономить

Документация [local-models](https://docs.openclaw.ai/gateway/local-models):

> Aim for 2+ maxed-out Mac Studios or an equivalent GPU rig (~$30k+) for a comfortable agent loop

и:

> **Always run the largest / full-size variant you can host**

DGX эту планку перекрывает. Брать вариант покрупнее — доки предупреждают, что мелкие и сильно квантованные модели *«truncate context and skip provider-side safety filters»*.

Требование из [gateway/security](https://docs.openclaw.ai/gateway/security), прямо про этот шаг:

> For tool-enabled agents or agents that read untrusted content, prompt-injection risk with
> older/smaller models is often too high. **Do not run those workloads on weak model tiers.**

Здесь есть натяжение, и его надо назвать вслух: **гео-ограничения гонят к локальным моделям, а документация запрещает давать инструменты слабым моделям.** Разрешается это только одним — на DGX можно позволить себе большую модель.

Ожидаемый результат: выбранная модель — крупнейший вариант, который машина тянет, а не первый попавшийся.
Если не так, то: не включать инструменты на слабой модели молча. Либо взять модель крупнее, либо остановиться и спросить человека.

### Шаг 5. 🚨 Безопасность — самый важный шаг. Песочницу не оставлять «как вышло»

Всё дословно из [gateway/security](https://docs.openclaw.ai/gateway/security).

**Модель угроз:**

> Your AI assistant can execute arbitrary shell commands, read/write files, access network
> services, and send messages to anyone (if given channel access). People who message it
> can try to trick it into doing bad things, social-engineer access to your data, or probe
> for infrastructure details.

**Это не граница безопасности:**

> OpenClaw is not a hostile multi-tenant security boundary for multiple adversarial users.

**Prompt injection системным промптом не лечится:**

> Prompt injection is not solved by system prompt guardrails alone—those are soft guidance;
> hard enforcement comes from tool policy, exec approvals, sandboxing, and channel allowlists.

**Песочница выключена по умолчанию** — [sandboxing](https://docs.openclaw.ai/gateway/sandboxing):

> Sandboxing is off by default and controlled by `agents.defaults.sandbox`

**Развилка, которую нельзя пропустить молча.** Ровно один из двух исходов:

1. **Включить песочницу** через `agents.defaults.sandbox` — допустимые значения взять из [sandboxing](https://docs.openclaw.ai/gateway/sandboxing). **Значения не угадывать**: в исходнике их нет.
2. **Явно доложить человеку**, что песочница остаётся выключенной, и получить его решение — до того, как агенту дадут инструменты.

Третьего нет. «Забыл» и «оставил по умолчанию» — это провал шага, а не нейтральный исход. Если цель — изоляция, правильный ответ вообще не здесь: [03-nemoclaw.md](../for-human/03-nemoclaw.md).

Безопасная база из документации — применить в `~/.openclaw/openclaw.json`:

```json5
{
  gateway: { mode: "local", bind: "loopback" },
  tools: { profile: "messaging" },
  exec: { security: "deny", ask: "always" }
}
```

Проверка после **любых** правок конфига:

```bash
openclaw security audit
openclaw security audit --deep
```

Ожидаемый результат: audit проходит.
Если не так, то: чинить по выводу audit, не глушить его. Правка конфига без последующего `openclaw security audit` — незакрытый шаг.

### Шаг 6. ⚠️ Ubuntu + AppArmor — прямо про этот DGX

Дословно:

> On Ubuntu/AppArmor hosts with Docker sandbox enabled, unprivileged user namespaces inside
> the container may fail. Run `openclaw doctor`; if it reports a Codex bwrap namespace probe
> failure, prefer an AppArmor profile that grants the required namespaces

То есть на Ubuntu песочница может **молча не завестись**. Включённая в конфиге ≠ работающая.

```bash
openclaw doctor
```

Ожидаемый результат: `doctor` не жалуется на namespaces.

Машинная проверка:

```bash
openclaw doctor 2>&1 | grep -i -E "bwrap|namespace"
```

Ожидаемый результат: **пусто**.
Если не так, то (сообщение про Codex bwrap namespace probe failure): песочница **не работает**, несмотря на конфиг. Не считать шаг 5 выполненным. Взять AppArmor-профиль, дающий нужные namespaces, и перепроверить `openclaw doctor`. Если не вышло — остановиться и доложить человеку, что песочница включена в конфиге, но не работает фактически.

### Шаг 7. Файлы личности агента

Рабочая папка — `~/.openclaw/workspace`. Там живёт «душа» агента — [agent-workspace](https://github.com/openclaw/openclaw/blob/main/docs/concepts/agent-workspace.md):

| Файл | Что задаёт |
|---|---|
| **`SOUL.md`** | характер, тон, границы |
| `AGENTS.md` | инструкции по работе и памяти |
| `USER.md` | кто ты и как к тебе обращаться |
| `IDENTITY.md` | имя агента, стиль, эмодзи |
| `TOOLS.md` | заметки про твои инструменты |
| `MEMORY.md` | долговременная память |

Про `SOUL.md` из [документации](https://github.com/openclaw/openclaw/blob/main/docs/concepts/soul.md):

> `SOUL.md` is where your agent's voice lives… OpenClaw injects it into normal sessions,
> so it carries real weight

Главный конфиг — `~/.openclaw/openclaw.json`.

Ожидаемый результат: файлы личности — содержательное решение человека, не агента. Заполнять их без указаний человека не требуется; установка от этого не ломается.
Если не так, то: не выдумывать личность за человека. Оставить как есть и сообщить, где эти файлы лежат.

---

## Справочно: прокси

На локальной Ollama прокси не нужен — трафик не покидает машину. **Не настраивать без явного указания человека.** Раздел здесь только чтобы не искать.

Официально поддерживается — [security/network-proxy](https://docs.openclaw.ai/security/network-proxy):

```json5
{
  proxy: {
    enabled: true,
    proxyUrl: "http://127.0.0.1:3128",
    loopbackMode: "gateway-only"
  }
}
```

Есть и переменная `OPENCLAW_PROXY_URL`. Оговорки из документации:

- *«This is process-level coverage for JavaScript HTTP/WebSocket clients, not an OS-level network sandbox»*
- пока прокси активен, OpenClaw **очищает** `no_proxy`/`NO_PROXY`
- IRC идёт сырым TCP/TLS и **не проксируется**
- переменные `HTTP_PROXY`/`HTTPS_PROXY` **не проксируют встроенный браузер**

---

## Справочно: родословная — почему столько имён

Из [официальной страницы истории](https://docs.openclaw.ai/start/lore):

**Warelay** → **Clawd / Clawdbot** (25 ноя 2025 – 27 янв 2026) → **Molty / Moltbot** (27–30 янв 2026) → **OpenClaw** (с 30 янв 2026).

Причина первого переименования, дословно: Anthropic прислала *«a polite email asking for a name change (trademark stuff)»*. Второе — *«That name never quite rolled off the tongue either»*, а сообщество проголосовало за OpenClaw, *«because molting is what lobsters do to grow»*.

Практическое следствие для агента: на очень старых установках может остаться служба `clawdbot-gateway.service`. Команда `openclaw uninstall` убирает её автоматически.

---

## Стоп-условия

Не делать. Остановиться и спросить человека:

| Ситуация | Почему стоп |
|---|---|
| **Подключать каналы связи** (Telegram, WhatsApp, Slack, Discord, Signal, Matrix…) без явного указания человека | канал = внешние люди, пишущие агенту, который выполняет произвольные shell-команды. `channel allowlists` — часть hard enforcement, не декорация |
| **Выставлять шлюз за пределы loopback** (порт 18789) без явного указания человека | база из доков — `gateway: { mode: "local", bind: "loopback" }`. OpenClaw *«is not a hostile multi-tenant security boundary»* |
| **Молча оставить песочницу выключенной** | `agents.defaults.sandbox` выключен по умолчанию; «оставил как вышло» — провал Шага 5. Либо включить, либо явно доложить человеку |
| Угадывать значения `agents.defaults.sandbox` | в исходнике их нет; брать из [sandboxing](https://docs.openclaw.ai/gateway/sandboxing) |
| `openclaw doctor` сообщает про bwrap/namespace failure, а починить не вышло | песочница не работает фактически. Докладывать, а не умалчивать |
| Ставить `/v1` в адрес Ollama, копируя из 04-hermes.md / 05-ouroboros.md | *«It breaks tool calling and models can emit raw tool-call JSON as plain text»* |
| Дать инструменты слабой/мелкой/сильно квантованной модели | *«Do not run those workloads on weak model tiers»* |
| Лечить prompt injection правкой системного промпта / `SOUL.md` | *«Prompt injection is not solved by system prompt guardrails alone»* — это soft guidance |
| Править конфиг и не прогнать `openclaw security audit` | незакрытый шаг |
| Цель установки — изоляция | это не та инструкция. [03-nemoclaw.md](../for-human/03-nemoclaw.md) |
| Не отработали обе ветки шага 1 (install.sh и npm) | дальше — догадки |
| Не выполнена 00-ollama.md | фундамента нет |

---

## Критерий готовности

```bash
openclaw --version
```
→ печатает версию.

```bash
openclaw doctor 2>&1 | grep -i -E "bwrap|namespace"
```
→ **пусто** (песочница не сломана молча).

```bash
openclaw gateway status
```
→ работает.

```bash
openclaw models status
```
→ показывает `ollama/...`.

```bash
grep -rn "11434/v1" ~/.openclaw/ ; env | grep -i "11434/v1"
```
→ **пусто из обеих команд**. Адрес Ollama без `/v1`.

```bash
openclaw security audit
```
→ проходит.

**Главная проверка — инструменты выполняются, а не печатаются текстом.** В **локальной** сессии агента (не через канал связи — см. «Стоп-условия»; способ запуска сессии — из [docs.openclaw.ai](https://docs.openclaw.ai/), команду не угадывать) дать задачу, требующую инструмента:

> создай файл `~/.openclaw/workspace/tool-check.txt` со словом `ok`

Затем:

```bash
cat ~/.openclaw/workspace/tool-check.txt
```

Ожидаемый результат: `ok`. Файл существует ⇒ инструмент реально выполнился.
Если не так, то: файла нет, а в ответе агента виден JSON вызова инструмента текстом ⇒ в адресе Ollama остался `/v1`. Вернуться к Шагу 3. Это не «тупая модель».

Финальный пункт, который нельзя отметить автоматически:

- [ ] решение по песочнице **принято и зафиксировано** — включена и проверена через `openclaw doctor`, либо явно доложено человеку, что она выключена. Не «оставил как вышло».
