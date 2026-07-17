# 07. Перенос навыков из Perplexity — рецепт для AI-кодера

Цель: взять навык (Skill), созданный человеком в Perplexity, и установить его в Claude Code,
Hermes, OpenClaw, NemoClaw и Ouroboros так, чтобы он реально загружался.

Формат навыка у всех шести совместим: `SKILL.md` с YAML-frontmatter и markdown-телом.
Hermes и OpenClaw заявляют соответствие [agentskills.io](https://agentskills.io/specification).

**Подтверждённый минимум для Perplexity My Skills** (по
[официальной справке](https://www.perplexity.ai/help-center/en/articles/13914413-how-to-use-computer-skills)):
импорт — один `.md` либо `.zip` с `SKILL.md` в корне, до **10 МБ**; frontmatter обязан
содержать **`name`** (lowercase, дефисы, 1–64 символа) и **`description`**.

> **NOT VERIFIED — важно не перепутать источники.**
> [Research-статья Perplexity](https://research.perplexity.ai/articles/designing-refining-and-maintaining-agent-skills-at-perplexity)
> описывает расширенный каталог (`scripts/`, `references/`, `assets/`, `config.json`,
> поля `depends`, `metadata`) — но это **внутренний фреймворк Perplexity Computer**, и сама
> статья называет эти элементы **возможными, а не обязательными**. Публичная схема My Skills
> их обязательными не объявляет. **Не требовать их от человека и не достраивать самому.**
> Работать по минимальному формату; всё сверх него переносить как есть, если оно уже есть.

---

## 🛑 Прочитать до первой команды

**Выгрузить навык из Perplexity автоматически невозможно.** API навыков не существует:
поиск по слову `skill` в машинном индексе всей документации
[`docs.perplexity.ai/llms.txt`](https://docs.perplexity.ai/llms.txt) даёт **ноль совпадений**.
Официальная справка описывает только создание, импорт и удаление — действий
Download / Export / Copy Source в ней нет.

Из этого следует правило, нарушение которого недопустимо:

**Исходный `SKILL.md` предоставляет человек. Ты его не добываешь и не сочиняешь.**

Если человек не дал файл или текст навыка — остановиться и попросить. Не искать обходные пути,
не ставить расширения, не звать сторонние MCP-серверы. См. «Стоп-условия».

---

## Предусловия

Человек предоставил исходник навыка: папку с `SKILL.md` либо текст навыка.

```bash
ls -R ./my-skill/
```

Ожидаемый результат: присутствует файл `SKILL.md`. Могут присутствовать `scripts/`,
`references/`, `assets/`, `config.json`.
Если не так, то: остановиться, запросить исходник у человека. Дальше не идти.

```bash
head -20 ./my-skill/SKILL.md
```

Ожидаемый результат: YAML-frontmatter между `---`, в нём как минимум `name` и `description`.
Если не так, то: остановиться. Файл без frontmatter навыком не является — уточнить у человека,
тот ли это файл.

Целевые агенты установлены по инструкциям [01](../for-human/01-claude-code-local.md),
[03](../for-human/03-nemoclaw.md), [04](../for-human/04-hermes.md),
[05](../for-human/05-ouroboros.md), [06](../for-human/06-openclaw.md). Ставить навык в
неустановленного агента не нужно — пропустить его шаг.

---

## Переменные

| Переменная | Значение | Смысл |
|---|---|---|
| `SKILL_NAME` | из поля `name` в frontmatter | обязан совпадать с именем папки |
| Исходник | `./my-skill/` | папка, которую дал человек |
| Claude Code | `~/.claude/skills/` | |
| Hermes | `~/.hermes/skills/` | *«the primary directory and source of truth»* |
| OpenClaw | `~/.agents/skills/` | приоритет 3 из 6; выбран, т.к. на него же можно нацелить Hermes |
| NemoClaw | только `skill install` | песочница, `cp` не работает |
| Ouroboros | `~/Ouroboros/data/skills/external/` | требует ревью перед запуском |

---

## Шаги

### Шаг 1. Прочитать frontmatter и зафиксировать имя

```bash
sed -n '/^---$/,/^---$/p' ./my-skill/SKILL.md
```

Ожидаемый результат: видны поля `name` и `description`. Значение `name` — только нижний
регистр, без пробелов, допустимы дефисы.
Если не так, то: остановиться, сообщить человеку, какое поле не соответствует. Не исправлять
`name` самостоятельно — от него зависит имя папки во всех пяти местах.

Проверить совпадение имени папки и поля `name`:

```bash
grep -E "^name:" ./my-skill/SKILL.md
basename $(realpath ./my-skill)
```

Ожидаемый результат: значения совпадают.
Если не так, то: переименовать **папку** под `name`, а не наоборот. Поле `name` — источник истины.

### Шаг 2. Добавить `version`, если его нет

Ouroboros требует `version` как обязательное поле —
[docs/CREATING_SKILLS.md](https://github.com/razzant/ouroboros/blob/main/docs/CREATING_SKILLS.md)
(обязательные: `name` ≤64 символов, `description`, `version`). У навыков Perplexity этого
поля нет.

```bash
grep -qE "^version:" ./my-skill/SKILL.md && echo "version есть" || echo "version отсутствует"
```

Если отсутствует — добавить строку в frontmatter:

```yaml
version: 1.0.0
```

Ожидаемый результат: `version` присутствует.
Если не так, то: не продолжать установку в Ouroboros — манифест не пройдёт валидацию.
Остальные агенты лишнее поле игнорируют, поэтому добавлять его всем безопасно.

### Шаг 3. Проверить длину `description`

OpenClaw требует: одна строка, меньше 160 символов —
[docs/tools/skills.md](https://github.com/openclaw/openclaw/blob/main/docs/tools/skills.md).

```bash
grep -E "^description:" ./my-skill/SKILL.md | wc -c
```

Ожидаемый результат: меньше 160.
Если не так, то: **остановиться и предложить человеку сокращённый вариант, не сокращать молча.**
`description` — это триггер загрузки навыка, дословно из статьи Perplexity:

> The description is the routing trigger… instructions for the model for when to load the Skill.

Неудачное сокращение сломает навык тише, чем неверный путь: файл будет на месте, а грузиться
перестанет. Сокращение обязано сохранять **условие загрузки** («когда брать»), а не описание
функции («что делает»).

### Шаг 4. Claude Code

```bash
mkdir -p ~/.claude/skills
cp -r ./my-skill ~/.claude/skills/
ls ~/.claude/skills/my-skill/SKILL.md
```

Ожидаемый результат: путь к файлу напечатан.
Если не так, то: проверить права на `~/.claude/skills`.

### Шаг 5. Hermes

```bash
mkdir -p ~/.hermes/skills
cp -r ./my-skill ~/.hermes/skills/
ls ~/.hermes/skills/my-skill/SKILL.md
```

Ожидаемый результат: путь напечатан.

Каталог подтверждён документацией как основной —
[features/skills.md](https://github.com/NousResearch/hermes-agent/blob/main/website/docs/user-guide/features/skills.md).
Hermes поддерживает и внешние каталоги через `skills.external_dirs` в `~/.hermes/config.yaml`
(подтверждено в коде: `agent/skill_utils.py`). Если человек просил единый каталог — см. Шаг 9.

Проверка:

```bash
hermes
```

В сессии: навык обязан быть доступен как слеш-команда `/my-skill` — каждый навык Hermes
автоматически становится командой.
Если не так, то: проверить frontmatter и перезапустить Hermes.

### Шаг 6. OpenClaw

```bash
mkdir -p ~/.agents/skills
cp -r ./my-skill ~/.agents/skills/
ls ~/.agents/skills/my-skill/SKILL.md
```

Ожидаемый результат: путь напечатан.

Порядок поиска навыков у OpenClaw, по убыванию приоритета: `<workspace>/skills` →
`<workspace>/.agents/skills` → **`~/.agents/skills`** → `~/.openclaw/skills` → встроенные →
`skills.load.extraDirs`.

> ⚠️ **Не использовать `dz init --target openclaude`.** Адаптер `@dzhechkov/adapter-openclaude`
> (v0.1.0) пишет в `~/.openclaude/skills/`, тогда как OpenClaw читает `~/.openclaw/skills`.
> `.openclaude` ≠ `.openclaw` — команда отработает успешно, навыков не будет. Отказ тихий.
> Проверено чтением адаптера. Для Hermes тот же CLI пишет в `~/.hermes/skills` — там путь верный.

### Шаг 7. NemoClaw

`cp` здесь не работает: файлы надо занести **внутрь песочницы**.

```bash
nemohermes my-assistant skill install ./my-skill/
```

Для OpenClaw в песочнице: `nemoclaw <имя-песочницы> skill install ./my-skill/`.

Ожидаемый результат: команда завершилась без ошибки. Навык окажется в
`/sandbox/.hermes/skills/my-skill` либо `/sandbox/.openclaw/skills/my-skill`.
Если не так, то: проверить имя песочницы и что она запущена.

Требования к имени у NemoClaw строже: только буквы, цифры, точки, дефисы, подчёркивания.
Файлы, начинающиеся с точки, пропускаются; пути с небезопасными символами отклоняются.

Навык переживает пересборку песочницы — каталог `skills` входит в `state_dirs`.

> 🛑 **`skill install` — не для плагинов.** Дословно из документации NemoClaw:
> *«Do not use `skill install` for Hermes runtime plugins.»* Плагины (рантайм-код) ставятся
> только через собственный Dockerfile. Если то, что дал человек, содержит `plugin.yaml`
> или `plugin.py` — это не навык. Остановиться, см. «Стоп-условия».

### Шаг 8. Ouroboros

```bash
cp -r ./my-skill ~/Ouroboros/data/skills/external/
ls ~/Ouroboros/data/skills/external/my-skill/SKILL.md
```

Ожидаемый результат: путь напечатан.

**Навык не заработает от копирования.** Жизненный цикл: `install → review → enable → execute`.
Между установкой и запуском — **ревью тремя моделями**. До его прохождения навык не выполняется.

Ожидаемый результат: навык виден в интерфейсе Ouroboros со статусом, требующим ревью.
Если не так, то: проверить наличие `version` (Шаг 2) — без него манифест не валиден.

> 🛑 **Ревью не пропускать.** Кнопка «⚠️ Skip review» и эндпоинт
> `POST /api/owner/skills/{skill}/attest-review` — **действия владельца**. Агент не может
> выписать ревью сам: отметка лежит в owner-state. Не пытаться обойти. Сообщить человеку,
> что навык ждёт ревью, и остановиться.

### Шаг 9. Единый каталог (если человек просил)

Пять независимых копий расходятся. Единый источник:

```bash
mkdir -p ~/.agents/skills
```

- OpenClaw читает его штатно (приоритет 3) — настройка не нужна
- Hermes: добавить путь в `skills.external_dirs` в `~/.hermes/config.yaml`
- Claude Code, Ouroboros: симлинк или копия
- NemoClaw: **только `skill install`** — песочница внешние каталоги хоста не читает

Правку `~/.hermes/config.yaml` выполнять только по явной просьбе человека: файл общий
с другими настройками Hermes.

---

## Стоп-условия

Остановиться и спросить человека, если:

1. **Исходника навыка нет.** Не добывать его из Perplexity. API навыков не существует —
   проверено по исчерпывающему индексу `llms.txt` (ноль совпадений на `skill`). Отсутствие
   исходника — это вопрос к человеку, а не задача на исследование.

2. **Найден «экспортёр» Perplexity** — браузерное расширение, скрипт, сторонний MCP-сервер
   (`perplexity-user-mcp`, `perplexity-web-api-mcp`, `perplexity-exporter` и подобные).
   **Не устанавливать, не запускать, не предлагать как решение.** Все они работают через
   **сессионные куки человека** и реверс приватного веб-API. Один из них прямо пишет о себе:
   *«Not affiliated with Perplexity AI, Inc.»* Цепочка риска: доступ к сессии → полный доступ
   к аккаунту Perplexity → переписка, платёжные данные, всё остальное. Ради переноса
   текстового файла это неприемлемый размен.

3. **Содержимое навыка неизвестно.** Никогда не сочинять тело `SKILL.md`, поля frontmatter,
   имя или описание. Придуманный навык выглядит рабочим и делает не то.

4. **`description` длиннее 160 символов.** Предложить сокращение, дождаться подтверждения.
   Молчаливое сокращение ломает загрузку навыка незаметно.

5. **То, что дал человек, содержит `plugin.yaml`, `plugin.py` или `__init__.py` с `register()`.**
   Это плагин, а не навык. Плагины ставятся иначе, а в NemoClaw — только своим Dockerfile.

6. **Ouroboros требует ревью.** Не обходить, не жать «Skip review» от имени человека,
   не звать `attest-review`. Это owner-действие.

7. **Путь в NemoClaw неоднозначен.** `.agents/skills/` в репозитории NemoClaw — это навыки
   для локального кодинг-агента человека, **не** для песочницы. Не путать с `skill install`.

---

## Критерий готовности

Проверяемо машиной:

```bash
# 1. Frontmatter полон
grep -E "^name:|^description:|^version:" ./my-skill/SKILL.md
```
Ожидается: три строки.

```bash
# 2. Имя папки = поле name
grep -E "^name:" ./my-skill/SKILL.md
basename $(realpath ./my-skill)
```
Ожидается: совпадение.

```bash
# 3. description влезает в лимит OpenClaw
grep -E "^description:" ./my-skill/SKILL.md | wc -c
```
Ожидается: меньше 160.

```bash
# 4. Файлы на местах
ls ~/.claude/skills/my-skill/SKILL.md
ls ~/.hermes/skills/my-skill/SKILL.md
ls ~/.agents/skills/my-skill/SKILL.md
ls ~/Ouroboros/data/skills/external/my-skill/SKILL.md
```
Ожидается: четыре пути напечатаны без ошибок.

```bash
# 5. В навык не утёк секрет
grep -rniE "api[_-]?key|token|secret|password|Bearer " ./my-skill/
```
Ожидается: **пусто**. Навык копируется в пять мест и, возможно, в git — секрет в нём
размножится. Нашлось совпадение: остановиться, сообщить человеку, не копировать.

Требует человека:

- Hermes: навык доступен как `/my-skill` в сессии
- OpenClaw: навык присутствует в списке навыков
- NemoClaw: `skill install` завершился без ошибки
- Ouroboros: навык прошёл ревью и переведён в `enabled`
- **Навык срабатывает на реальном запросе, попадающем под его `description`**

Последний пункт — единственный, который проверяет то, что важно. Навык может лежать по
правильному пути во всех пяти местах и не грузиться, потому что `description` не описывает
условие загрузки. При таком симптоме чинить описание, а не путь.
