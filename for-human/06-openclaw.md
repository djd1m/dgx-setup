# 06. OpenClaw — личный AI-ассистент

Требуется: выполненная инструкция [00-ollama.md](00-ollama.md).

Репозиторий: [github.com/openclaw/openclaw](https://github.com/openclaw/openclaw).
Документация: [docs.openclaw.ai](https://docs.openclaw.ai/).

## Что это

Дословно из [README](https://github.com/openclaw/openclaw):

> a *personal AI assistant* you run on your own devices. It answers you on the channels
> you already use.

29+ каналов связи (Telegram, WhatsApp, Slack, Discord, Signal, Matrix…), долговременная
память, управление браузером, доступ к файлам, выполнение команд, магазин плагинов.
Автор — Peter Steinberger, 346k+ звёзд.

---

## ⚠️ Сначала подумай: может, тебе нужен NemoClaw?

**У OpenClaw песочница по умолчанию выключена**, а он выполняет произвольные shell-команды.
[NemoClaw](03-nemoclaw.md) существует ровно для того, чтобы запускать OpenClaw **внутри
изолированной песочницы OpenShell**.

| Что ставить | Когда |
|---|---|
| **[03-nemoclaw.md](03-nemoclaw.md)** | нужен OpenClaw + изоляция. **Рекомендуется** |
| **Эта инструкция** | нужен OpenClaw сам по себе, изоляцию берёшь на себя |

Если сомневаешься — иди в 03.

---

## Шаг 0. Требования

**Node.js: 24.15+ (рекомендуется), либо 22.22.3+, либо 25.9+** —
[install](https://docs.openclaw.ai/install).

```bash
node --version
```

Docker **не обязателен**. Дословно: *«Docker is **optional**. Use it for an isolated,
throwaway gateway environment»* — [docker](https://docs.openclaw.ai/install/docker).

---

## Шаг 1. Установка

```bash
curl -fsSL https://openclaw.ai/install.sh | bash
```

Что делает этот скрипт (файл на 111.7 КБ, прочитан): ставит Node, если его нет (через
apt/pacman/dnf/yum/apk или NodeSource), проверяет версию SQLite в Node, глобально
устанавливает npm-пакет **`openclaw`**, чинит права npm на Linux. Для системных пакетов
нужен sudo; если зависимости уже стоят, повышение прав пропускается.

Либо напрямую через npm:

```bash
npm install -g openclaw@latest
openclaw onboard --install-daemon
```

Проверка:

```bash
openclaw --version
openclaw doctor
openclaw gateway status
```

Шлюз слушает порт **18789**.

---

## Шаг 2. Подключить Ollama — и одна критичная деталь

Правь `~/.openclaw/openclaw.json` (формат **JSON5**, не обычный JSON):

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

### 🔥 Адрес Ollama — БЕЗ `/v1`

Это главная ловушка. Дословное предупреждение из
[providers/ollama](https://docs.openclaw.ai/providers/ollama):

> **Do not use the `/v1` OpenAI-compatible URL** (`http://host:11434/v1`).
> It breaks tool calling and models can emit raw tool-call JSON as plain text.

| Программа | Адрес Ollama |
|---|---|
| **OpenClaw** | `http://127.0.0.1:11434` ← **без `/v1`** |
| Hermes, Ouroboros | `http://localhost:11434/v1` ← **с `/v1`** |
| Claude Code | `http://localhost:11434` |

Перепутаешь — агент начнёт печатать JSON вызовов инструментов текстом вместо их выполнения.
Симптом легко принять за «тупую модель».

### Про размер модели

Документация [local-models](https://docs.openclaw.ai/gateway/local-models) не стесняется:

> Aim for 2+ maxed-out Mac Studios or an equivalent GPU rig (~$30k+) for a comfortable agent loop

и:

> **Always run the largest / full-size variant you can host**

Твой DGX эту планку перекрывает. Бери вариант покрупнее — доки предупреждают, что мелкие
и сильно квантованные модели *«truncate context and skip provider-side safety filters»*.

---

## Шаг 3. Файлы личности агента

Рабочая папка — `~/.openclaw/workspace`. Там живёт «душа» агента —
[agent-workspace](https://github.com/openclaw/openclaw/blob/main/docs/concepts/agent-workspace.md):

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

---

## 🚨 Шаг 4. Безопасность — самый важный раздел

Авторы честны, поэтому просто цитирую. Всё дословно из
[gateway/security](https://docs.openclaw.ai/gateway/security).

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

**И предупреждение, которое прямо касается локальных моделей:**

> For tool-enabled agents or agents that read untrusted content, prompt-injection risk with
> older/smaller models is often too high. **Do not run those workloads on weak model tiers.**

Здесь есть натяжение, и его надо назвать вслух: **гео-ограничения гонят тебя к локальным
моделям, а документация запрещает давать инструменты слабым моделям.** Разрешается это
только одним — на DGX ты можешь позволить себе большую модель. Не экономь на её размере.

### Песочница выключена по умолчанию

> Sandboxing is off by default and controlled by `agents.defaults.sandbox`

— [sandboxing](https://docs.openclaw.ai/gateway/sandboxing)

Безопасная база из документации:

```json5
{
  gateway: { mode: "local", bind: "loopback" },
  tools: { profile: "messaging" },
  exec: { security: "deny", ask: "always" }
}
```

Проверка после любых правок:

```bash
openclaw security audit
openclaw security audit --deep
```

### ⚠️ Ubuntu + AppArmor — прямо про твой DGX

> On Ubuntu/AppArmor hosts with Docker sandbox enabled, unprivileged user namespaces inside
> the container may fail. Run `openclaw doctor`; if it reports a Codex bwrap namespace probe
> failure, prefer an AppArmor profile that grants the required namespaces

То есть на Ubuntu песочница может **молча не завестись**. Обязательно прогони `openclaw doctor`
и убедись, что она реально работает, а не только включена в конфиге.

---

## Родословная: почему столько имён

Из [официальной страницы истории](https://docs.openclaw.ai/start/lore):

**Warelay** → **Clawd / Clawdbot** (25 ноя 2025 – 27 янв 2026) → **Molty / Moltbot**
(27–30 янв 2026) → **OpenClaw** (с 30 янв 2026).

Причина первого переименования, дословно: Anthropic прислала *«a polite email asking for
a name change (trademark stuff)»*. Второе — *«That name never quite rolled off the tongue
either»*, а сообщество проголосовало за OpenClaw, *«because molting is what lobsters do to grow»*.

Практическое следствие: на очень старых установках может остаться служба
`clawdbot-gateway.service`. Команда `openclaw uninstall` убирает её автоматически.

---

## Про прокси

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

- *«This is process-level coverage for JavaScript HTTP/WebSocket clients, not an OS-level
  network sandbox»*
- пока прокси активен, OpenClaw **очищает** `no_proxy`/`NO_PROXY`
- IRC идёт сырым TCP/TLS и **не проксируется**
- переменные `HTTP_PROXY`/`HTTPS_PROXY` **не проксируют встроенный браузер**

На локальной Ollama прокси тебе не нужен — трафик не покидает машину.

---

## Готово, если

- [ ] `openclaw --version` печатает версию
- [ ] `openclaw doctor` не ругается (и **не жалуется на namespaces**, если включена песочница)
- [ ] `openclaw gateway status` — работает
- [ ] `openclaw models status` показывает `ollama/...`
- [ ] адрес Ollama **без `/v1`**
- [ ] `openclaw security audit` проходит
- [ ] агент выполняет команды, а не печатает JSON текстом
- [ ] ты решил, что делать с песочницей, а не оставил как вышло
