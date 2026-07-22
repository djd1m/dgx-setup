# 13. Hermes как автономный исполнитель инструкций — рецепт для ИИ-агента

**Цель:** настроить уже установленный Hermes ([04-hermes.md](04-hermes.md)) так, чтобы он мог
**автономно исполнять for-ai инструкции этого репозитория** (ставить Ollama и модели, настраивать
routing, деплоить агентов) — при этом **не зациклившись** и **не открыв хост настежь**.

**Роли в этом сценарии:**

| Роль | Чем закрыта |
|---|---|
| Исполнитель (руки, shell) | Hermes на хосте, terminal-бэкенд `local` |
| Мозг (решения) | **облачная модель Cloud.ru** (OpenAI-совместимый эндпоинт) |
| Веб-поиск | **Brave**, нативный бэкенд `brave-free` |

> 🚨 Мозг — **облачный**, а не локальная Ollama: Ollama в этом сценарии агент ещё только ставит,
> взять её же за мозг установщика нельзя (курица и яйцо). **Выбор облачной модели — по
> [12-cloud-brain-routing.md](12-cloud-brain-routing.md): рекомендован Qwen3-235B-A22B-Instruct-2507,
> НЕ Kimi.** От этого выбора напрямую зависит, доедет установка или мозг зациклится.

---

## 🚨 Прочитай до первой команды

- **Механически Hermes это может.** Терминал-инструмент гоняет настоящий shell на хосте
  ([tools](https://hermes-agent.nousresearch.com/docs/user-guide/features/tools),
  [security](https://hermes-agent.nousresearch.com/docs/user-guide/security)); агентный цикл
  крутится сам до `agent.max_turns` (дефолт **90**) —
  [agent-loop](https://hermes-agent.nousresearch.com/docs/developer-guide/agent-loop/); процедуру
  кодирует скилл ([skills](https://hermes-agent.nousresearch.com/docs/user-guide/features/skills)).
- **Но вслепую — НЕЛЬЗЯ.** Два независимых риска: (1) слабый мозг зацикливается на неверном
  вызове; (2) полный YOLO пропускает `curl install.sh | sh` на хост.
- **НЕ запускай автономную установку под полным YOLO.** Только `approvals.mode: smart` или
  точечный `command_allowlist` (см. Шаг 2).
- **Смоук-тест tool-calling — ПЕРВЫЙ шаг (Шаг 5).** Пока не подтверждён структурный `tool_calls`
  от Cloud.ru — ничего автономного не запускать.

---

## Предусловия

1. Hermes установлен и проходит `hermes doctor` — [04-hermes.md](04-hermes.md).
2. Есть доступ к Cloud.ru Foundation Models (OpenAI-совместимый эндпоинт) и ключ Brave.
3. Мозг выбран по [12-cloud-brain-routing.md](12-cloud-brain-routing.md).

**Проверка Hermes:**
```bash
hermes --version && hermes doctor
```
**Ожидаемый результат:** версия печатается, `doctor` без жалоб.
**Если не так, то:** вернись в [04-hermes.md](04-hermes.md), этот рецепт продолжать нельзя.

---

## Переменные

| Переменная | Значение | Примечание |
|---|---|---|
| `CLOUDRU_BASE_URL` | `https://<хост-cloud.ru>/v1` | **оканчивается на `/v1`**; Hermes сам добавит `/chat/completions` |
| `CLOUDRU_MODEL_ID` | из `/v1/models` | **NOT VERIFIED — не угадывать**, читать из живого эндпоинта |
| `OPENAI_API_KEY` | ключ Cloud.ru | в `.env`, НЕ в `config.yaml` |
| `BRAVE_SEARCH_API_KEY` | ключ Brave | **длинная** переменная, НЕ `BRAVE_API_KEY` |
| `HERMES_WRITE_SAFE_ROOT` | напр. `/opt/target` | сузить запись агента |

---

## Шаги

### Шаг 1. Бутстрап terminal-бэкенда

```bash
hermes setup terminal    # выбрать local
hermes setup model
hermes doctor
```

**Ожидаемый результат:** terminal-бэкенд настроен, `doctor` чист.

🛑 **Команды `hermes terminal` НЕ существует.** Только `hermes setup terminal` —
[cli-commands](https://raw.githubusercontent.com/NousResearch/hermes-agent/main/website/docs/reference/cli-commands.md).
Не изобретай флаг, не угадывай подкоманду.

### Шаг 2. Режим аппрувов — smart, НЕ YOLO

По [security](https://hermes-agent.nousresearch.com/docs/user-guide/security):

| Режим | Гейтит | Для установки на хост |
|---|---|---|
| `approvals.mode: smart` (дефолт) | вспомогательная LLM оценивает риск каждой команды | **ДА** |
| `--yolo` / `HERMES_YOLO_MODE=1` / `mode: off` | **только** hardline (`rm -rf /`, форк-бомба) | **НЕТ** |

🛑 **Под YOLO `curl install.sh | sh` РАЗРЕШЁН** — то есть агент скачает и выполнит произвольный
установщик из сети. Для сценария «качаем и ставим софт» это недопустимо.

Конфиг:
```yaml
approvals:
  mode: smart          # НЕ off, НЕ yolo
  timeout: 300
agent:
  max_turns: 150       # поднять под длинную установку (дефолт 90 может не хватить)
```

Сузить поверхность записи:
```bash
export HERMES_WRITE_SAFE_ROOT=/opt/target
```

**Ещё безопаснее полного smart:** одобрить **конкретный** инсталлятор через `command_allowlist`
вместо доверия LLM-гейту. Тогда автономность — ровно на проверенных глазами командах.

> ✅ Защита путей (`~/.ssh`, `~/.aws`, `.env`, `/etc/sudoers`) держится даже под YOLO
> ([security](https://hermes-agent.nousresearch.com/docs/user-guide/security)) — но это **не**
> причина включать YOLO: `curl | sh` от этого безопаснее не становится.

**Ожидаемый результат:** `hermes config show` → `approvals.mode: smart`.
**Если видишь `off` / YOLO активен, то:** СТОП, верни `smart`, не продолжай.

### Шаг 3. Мозг через Cloud.ru

Cloud.ru Foundation Models — OpenAI-совместимый эндпоинт, подтверждено
[skill Cloud.ru](https://raw.githubusercontent.com/cloud-ru/evo-aifactory-skills/main/cloudru-foundation-models/SKILL.md).
Настройка — как кастомный провайдер из [04-hermes.md](04-hermes.md):

```bash
# сначала прочитать реальный model-id — НЕ угадывать
curl -fsS "$CLOUDRU_BASE_URL/models" -H "Authorization: Bearer $OPENAI_API_KEY" | grep -o '"id":"[^"]*"'

hermes config set model.default        <ID-как-в-/v1/models>
hermes config set model.provider       openai-api
hermes config set model.base_url       "$CLOUDRU_BASE_URL"      # с /v1
hermes config set model.context_length 64000
```
Ключ — в `.env` как `OPENAI_API_KEY` (не в `config.yaml`).

**Ожидаемый результат:** `hermes config show` показывает заданный `base_url` (с `/v1`) и model-id.
**Если не так, то:** проверь `/v1` в `base_url` и совпадение model-id с `/v1/models` буква-в-букву.

🛑 **Точный `model-id` — только из `/v1/models` (NOT VERIFIED, не подставлять по памяти).**

**Если по какой-то причине используется Kimi K2.6** (по теме 12 рекомендован Qwen3-235B, не Kimi) —
жёсткие особенности API, [quickstart Kimi K2.6](https://platform.kimi.ai/docs/guide/kimi-k2-6-quickstart):
- температура **фиксирована** (1.0 thinking / 0.6 non-thinking) — иную слать = ошибка, лучше не слать;
- `tool_choice` **только** `auto`/`none`;
- `reasoning_content` **сохранять между ходами**.

Это дополнительный довод за Qwen3-235B: у него этих граблей нет.

### Шаг 4. Веб-поиск: Brave (нативный бэкенд)

По [web-search](https://raw.githubusercontent.com/NousResearch/hermes-agent/main/website/docs/user-guide/features/web-search.md):

```bash
# .env
BRAVE_SEARCH_API_KEY=<ключ Brave>
```
```yaml
# config.yaml — brave-free НЕ участвует в автодетекте, задать явно
web:
  search_backend: brave-free
```

🛑 **Переменная — `BRAVE_SEARCH_API_KEY` (длинная), НЕ `BRAVE_API_KEY`.** Community-плагин читает
**другую** переменную `BRAVE_API_KEY` — не смешивать. Впишешь короткую в расчёте на нативный
бэкенд — молча не подхватится.

⚠️ Нативный `brave-free` — **search-only**. Для `web_extract` нужен второй бэкенд (firecrawl/tavily).

**Ожидаемый результат:** `hermes config show` → `web.search_backend: brave-free`.

### Шаг 5. 🔴 Смоук-тест tool-calling — ПЕРВЫМ делом, ДО любой установки

Слабый/несовместимый мозг отдаёт вызовы инструментов **текстом в `content`** вместо структурного
поля `tool_calls`. Тогда никакой установки не будет — агент будет «рассказывать», что делает.
Это ловить **здесь**, а не на середине установки ([Kimi-K2](https://github.com/MoonshotAI/Kimi-K2)).

Проверка напрямую против Cloud.ru:
```bash
curl -fsS "$CLOUDRU_BASE_URL/chat/completions" \
  -H "Authorization: Bearer $OPENAI_API_KEY" -H "Content-Type: application/json" \
  -d '{"model":"'"$CLOUDRU_MODEL_ID"'","messages":[{"role":"user","content":"What is the weather in Moscow? Use the tool."}],
       "tools":[{"type":"function","function":{"name":"get_weather","description":"weather","parameters":{"type":"object","properties":{"city":{"type":"string"}},"required":["city"]}}}],
       "tool_choice":"auto"}' | grep -o '"finish_reason":"[^"]*"\|"tool_calls"'
```

**PASS, если:** в ответе есть структурный `"tool_calls"` **и** `"finish_reason":"tool_calls"`.
**FAIL, если:** вызов пришёл текстом в `content`, а `finish_reason` = `stop`.

**Если FAIL, то: 🛑 СТОП.** Автономный прогон не запускать. Причина — модель/эндпоинт не отдаёт
структурный tool-calling; смени модель (тема 12) или сверь параметры Cloud.ru. Не «попробуй ещё».

---

## Ядро темы: 10 усилений for-ai доков под слабый мозг

Скелет наших for-ai инструкций (`preconditions → command → expected → if-not → readiness → stop`)
**правильный**. Слабый мозг спотыкается не на скелете, а на его **пустых слотах**. При написании/
исполнении инструкций для облачного мозга-исполнителя обеспечь все десять пунктов ниже — это и есть
предмет темы 13 для for-ai.

### 1. Verify-after-step с машинно-проверяемым assertion
Каждый шаг закрывается проверкой на exit-код или **точную подстроку**, а не «на глаз»
([writing tools for agents](https://www.anthropic.com/engineering/writing-tools-for-agents)):
```bash
systemctl is-active ollama
curl -fsS localhost:11434/api/tags | grep -q '"models"'
```

### 2. Идемпотентность
Повторный прогон не должен ломать сделанное
([idempotent automation](https://devopsaitoolkit.com/blog/writing-idempotent-automation-scripts/)):
```bash
mkdir -p /opt/target
grep -qxF 'line' file || echo 'line' >> file
id someuser &>/dev/null || useradd someuser
[[ -f /opt/target/.step3.done ]] || { do_step3 && touch /opt/target/.step3.done; }
# атомарная запись: tmp=$(mktemp) ; ... > "$tmp" ; mv "$tmp" target
```

### 3. Circuit breaker
Максимум **2 попытки** на шаг → **STOP и доклад**. Запрет слепых retry. Обрезанный вывод = провал,
а не «наверное ок» ([Kimi K2 agent setup](https://platform.kimi.ai/docs/guide/use-kimi-k2-to-setup-agent)).

### 4. No-guess
Не выдумывать пути, порты, версии. Ненаблюдённое = **unknown → STOP-and-ask**, не «вероятно так».

### 5. Точные expected-выводы
Литеральный текст/JSON как критерий, семантические имена сервисов/файлов
([writing tools for agents](https://www.anthropic.com/engineering/writing-tools-for-agents)).

### 6. `if-not` = конкретное лечение
Сигнатура ошибки + **одна** команда исправления ИЛИ явный STOP. **Не** вываливать трейсбек как
«лечение».

### 7. Ловушка sudo-в-контейнере
Если terminal-бэкенд — контейнер и агент уже root, `sudo` может отсутствовать. Шим
([sudo inside docker](https://www.dash0.com/faq/how-to-use-sudo-inside-a-docker-container)):
```bash
sudo(){ [[ "$EUID" == 0 ]] || set -- command sudo "$@"; "$@"; }
```

### 8. `set -euo pipefail`
Особенно **`-u`** вскрывает незаполненные `${PLACEHOLDER}` до того, как они натворят бед
([set -euo pipefail](https://www.namehero.com/blog/how-to-use-set-e-o-pipefail-in-bash-and-why/)):
```bash
set -euo pipefail
```

### 9. Сократить поверхность решений
Один детерминированный вызов на шаг; сложное — в проверенный `scripts/`; ветвление —
таблицей-lookup, а не прозой; ≤ 5–6 инструментов
([taming tool calling](https://trilogyai.substack.com/p/taming-tool-calling-with-kimi-k25)).

### 10. Смоук-тест tool-calling ПЕРВЫМ шагом
См. Шаг 5. Структурный `tool_calls` + `finish_reason=tool_calls`, а не текст в `content`
([Kimi-K2](https://github.com/MoonshotAI/Kimi-K2)).

---

## Стоп-условия

Немедленно остановись и доложи человеку, если:

1. **Возник соблазн включить полный YOLO** (`--yolo` / `HERMES_YOLO_MODE=1` / `approvals.mode: off`)
   для автономного прогона на хосте. `curl install.sh | sh` под YOLO **разрешён** — это открывает
   хост. Только `smart` или `command_allowlist`.
2. **Смоук-тест tool-calling (Шаг 5) FAIL** — вызовы идут текстом, а не структурным `tool_calls`.
   Не запускать автономный прогон. Сменить модель (тема 12) / сверить Cloud.ru.
3. **Мозг зациклился** — повторяет тот же вызов после 2 попыток. Это симптом слабого мозга
   ([Kimi K2 accuracy](https://vllm.ai/blog/2025-10-28-kimi-k2-accuracy),
   [taming tool calling](https://trilogyai.substack.com/p/taming-tool-calling-with-kimi-k25)).
   **STOP, а не «попробуй ещё».** Лечится сменой модели (тема 12), не количеством попыток.
4. **Секрет утёк за `.env`.** Ключ Cloud.ru (`OPENAI_API_KEY`), ключ Brave
   (`BRAVE_SEARCH_API_KEY`) — только в `.env`, не в `config.yaml`, не в git, не в лог/транскрипт.
5. **Model-id угадан, а не прочитан из `/v1/models`** — остановись, прочитай реальный.

---

## NOT VERIFIED

> **«Ouroboros» как ФИЧА OpenClaw — НЕ подтверждено первоисточниками.** Автономная петля самого
> OpenClaw называется **«Ralph Loop»** (и то вторичка). В **нашем** репозитории **Ouroboros** и
> **OpenClaw** — **ОТДЕЛЬНЫЕ** агенты (см. [05](05-ouroboros.md), [06](06-openclaw.md),
> [11](11-multi-agent-host.md)) — так и писать. Сверяй имена перед автоматизацией.

> **Точный Cloud.ru `model-id`** — только из `/v1/models`. Не подставлять по памяти.

> **Docker-hardening флаги Hermes** (`--cap-drop`, `pids-limit`) в процитированных доках
> **НЕ найдены** — не полагаться как на существующие.

> **Числа бенчмарков Kimi K2.6** — vendor self-reported, не независимый замер.

---

## Критерий готовности

```bash
hermes config show | grep -qE 'mode:\s*smart'                    && echo "APPROVALS_OK"  || echo "APPROVALS_FAIL"
hermes config show | grep -qF '/v1'                              && echo "BASEURL_OK"    || echo "BASEURL_FAIL"
hermes config show | grep -qF 'brave-free'                       && echo "BRAVE_OK"      || echo "BRAVE_FAIL"
grep -q '^BRAVE_SEARCH_API_KEY=..*' ~/.hermes/.env               && echo "BRAVEKEY_OK"   || echo "BRAVEKEY_MISSING"
```
Проверка на утечку ключей — **должна быть пустой**:
```bash
cd ~/.hermes 2>/dev/null && git ls-files 2>/dev/null | xargs -r grep -lE 'BRAVE_SEARCH_API_KEY=..|OPENAI_API_KEY=..' ; echo "SECRET_LEAK_CHECK_DONE"
```

Итоговый чек-лист:

- [ ] `approvals.mode: smart` (или точечный `command_allowlist`) — **НЕ** YOLO
- [ ] `agent.max_turns` поднят под установку (напр. 150)
- [ ] terminal-бэкенд через `hermes setup terminal` (local), `hermes doctor` чист
- [ ] мозг — облачная модель из темы 12 (Qwen3-235B, **не** Kimi), `base_url` с `/v1`
- [ ] `model-id` прочитан из `/v1/models`, а не угадан
- [ ] Brave: `BRAVE_SEARCH_API_KEY` + `web.search_backend: brave-free`
- [ ] **Шаг 5 PASS**: Cloud.ru отдаёт структурный `tool_calls` + `finish_reason=tool_calls`
- [ ] исполняемые for-ai инструкции покрывают все 10 усилений
- [ ] ключи Cloud.ru и Brave только в `.env`, не в git
