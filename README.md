# Установка AI-агентов на NVIDIA DGX Spark / GB10 (aarch64, DGX OS)

Набор инструкций по развёртыванию локального AI-стека на DGX: **Ollama** как движок
инференса и несколько агентов поверх него — Claude Code, NemoClaw, Hermes, Ouroboros,
OpenClaw, плюс подключение к Cloud.ru Foundation Models.

**Целевая машина — DGX Spark на чипе [GB10 Grace Blackwell](https://docs.nvidia.com/dgx/dgx-spark/hardware.html)**,
включая машины того же класса под чужим брендом (например,
[Dell Pro Max with GB10](https://www.dell.com/en-us/shop/desktop-computers/dell-pro-max-with-gb10/spd/dell-pro-max-fcm1253-micro)).
Это **`aarch64`**, а не x86_64: Grace — процессор на архитектуре Arm.
Первое, что стоит выполнить, — `uname -m`.

> **NOT VERIFIED:** что Dell Pro Max with GB10 — **официально** OEM-версия DGX Spark.
> Dell этого слова не употребляет, называет продукт «AI Accelerator»; вывод построен на
> совпадении спецификаций. На практике это ничего не меняет — подробности в
> [00-ollama.md](for-human/00-ollama.md).

> ⚠️ **Если у тебя классический x86-DGX** с отдельными картами A100/H100 — инструкции
> в целом подойдут, но два места читай критически: **архитектура бинарников** (`amd64`
> вместо `arm64`) и **выбор моделей**. Второе важнее: рекомендации по моделям построены
> вокруг особенности GB10, которой у обычных карт нет. Первым делом выполни `uname -m`.

Все инструкции — в двух вариантах:

| Папка | Для кого | Как читать |
|---|---|---|
| [`for-human/`](for-human/) | для человека | объяснения, зачем каждый шаг, что может пойти не так |
| [`for-ai/`](for-ai/) | для AI-кодера | исполняемый рецепт: команды, проверки, критерии готовности |

**Точки входа в ветку для AI-кодера** (нумерация шагов внутри неё своя — не смешивай с человеческой):
[00 Ollama](for-ai/00-ollama.md) ·
[01 Claude Code](for-ai/01-claude-code-local.md) ·
[02 Cloud.ru](for-ai/02-claude-code-cloudru.md) ·
[03 NemoClaw](for-ai/03-nemoclaw.md) ·
[04 Hermes](for-ai/04-hermes.md) ·
[05 Ouroboros](for-ai/05-ouroboros.md) ·
[06 OpenClaw](for-ai/06-openclaw.md) ·
[07 Навыки](for-ai/07-skills-migration.md) ·
[08 vLLM](for-ai/08-vllm-vs-ollama.md)

## Главная идея: DGX — это сервер инференса, а не клиент чужого API

Все инструкции построены вокруг одного принципа: **модель работает на твоём железе**.
Это не идеология, а следствие трёх проверенных фактов:

1. **Ни Anthropic, ни OpenAI не обслуживают Россию — у каждого свой источник.**

   **Anthropic:** страна входит в системные требования Claude Code наравне с ОС и памятью —
   [Advanced setup](https://code.claude.com/docs/en/setup),
   [список поддерживаемых стран](https://www.anthropic.com/supported-countries).

   **OpenAI:** России нет **ни в одном** из двух списков — ни для
   [API](https://developers.openai.com/api/docs/supported-countries), ни для
   [ChatGPT](https://help.openai.com/en/articles/7947663-chatgpt-supported-countries).
   Причём OpenAI сама задаёт правило чтения — список **закрытый**, дословно:

   > We do not publish a separate list of countries and territories that we do not support.
   > **If a location is not included in the list below, our API is not supported there.**

   И называет последствие:

   > Accessing or offering access to our services outside of the countries and territories
   > listed below **may result in your account being blocked or suspended**.

   Проверено на живой странице: страны на «R» — только Romania и Rwanda. Беларуси нет.
   Украина есть с оговоркой `(with certain exceptions)`.

   > **Две оговорки, чтобы не подменять основания.** Россия исключена **списком стран**,
   > а не санкционным пунктом: в [ToS](https://openai.com/policies/terms-of-use/) раздел
   > Trade controls сформулирован общо («U.S. embargoed country or territory»), и **Россия
   > в нём не названа** — она не является comprehensively embargoed страной в смысле США,
   > в отличие от Кубы, Ирана, КНДР и Сирии. Это разные вещи.
   >
   > Отдельно: `help.openai.com` отдаёт 403 любому не-браузерному клиенту. Страница API
   > (`developers.openai.com`) читается напрямую и проверена; ChatGPT-список сверялся через
   > архивные снимки официальной страницы.
2. **NVIDIA в лицензионном соглашении прямо называет Россию** в списке ограниченных
   направлений — [NVIDIA Software License Agreement](https://www.nvidia.com/en-us/agreements/enterprise-software/nvidia-software-license-agreement/),
   а [Technology Access ToU](https://developer.nvidia.com/legal/terms) требуют подтвердить,
   что вы не проживаете в стране под эмбарго США.
3. **У Ollama никаких ограничений по географии нет.**

Отсюда вывод: **локальные модели снимают вопрос целиком.** Ничьего разрешения не нужно,
аккаунты не нужны, ключи не нужны. Именно поэтому [`00-ollama`](for-human/00-ollama.md)
идёт первым — на нём стоит всё остальное.

## Порядок установки

Порядок не произвольный — он отражает зависимости.

| № | Инструкция | Зачем | Зависит от |
|---|---|---|---|
| 00 | [Ollama + выбор моделей](for-human/00-ollama.md) | движок инференса, фундамент всего | — |
| 01 | [Claude Code на локальной Ollama](for-human/01-claude-code-local.md) | кодинг-агент без аккаунта Anthropic | 00 |
| 02 | [Claude Code через Cloud.ru](for-human/02-claude-code-cloudru.md) | если нужны модели мощнее, чем тянет DGX | — |
| 03 | [NemoClaw + OpenShell](for-human/03-nemoclaw.md) | песочница NVIDIA для агентов | 00 |
| 04 | [Hermes Agent](for-human/04-hermes.md) | самообучающийся агент от Nous Research | 00 |
| 05 | [Ouroboros](for-human/05-ouroboros.md) | самомодифицирующийся агент | 00 |
| 06 | [OpenClaw](for-human/06-openclaw.md) | личный ассистент, 29+ каналов связи | 00 |
| 07 | [Перенос навыков из Perplexity](for-human/07-skills-migration.md) | один навык — во всех агентах сразу | любой из 01/03–06 |
| 08 | [vLLM вместо Ollama?](for-human/08-vllm-vs-ollama.md) | разбор вопроса. Ответ — **нет**, и вот почему | 00 |

**Важно про 03 и 06.** NemoClaw — не агент и не модель. Это обёртка, которая запускает
**OpenClaw или Hermes внутри песочницы OpenShell**:

```
NemoClaw  ──управляет──>  OpenShell  ──изолирует и запускает──>  OpenClaw / Hermes
```

Если ставить OpenClaw ради безопасности — ставь его через NemoClaw (03), а не отдельно (06).
Инструкция 06 нужна тем, кому OpenClaw требуется сам по себе.

## Два разных «прокси» — не перепутай

В этих инструкциях прокси упоминается, и важно понимать, зачем именно.

| | Обход правил сервиса | Обход блокировки провайдера |
|---|---|---|
| Пример | Anthropic API из России | `ollama pull`, `raw.githubusercontent.com` |
| Кто запрещает | сам сервис (страна в требованиях) | российские провайдеры |
| Статус | **в этих инструкциях не описывается** | описывается, это нормально |

Почему `ollama pull` вообще не работает: `registry.ollama.ai` стоит за Cloudflare, а
российские провайдеры с 9 июня 2025 режут контент из-за Cloudflare на первых 16 КБ —
[заявление Cloudflare](https://blog.cloudflare.com/russian-internet-users-are-unable-to-access-the-open-internet/),
[issue в Ollama](https://github.com/ollama/ollama/issues/11583). Ollama рада тебя обслужить;
до неё просто не доходит трафик. Это принципиально другая ситуация, чем гео-ограничение сервиса.

## Уровень доверия к источникам

Все инструкции собраны в режиме **paranoid**: каждый факт подтверждён первоисточником,
ссылки кликабельные и ведут на официальную документацию или исходный код. Где проверить
не удалось — так и написано, **NOT VERIFIED**, без догадок.

Что это дало на практике — находки, которых нет ни в одном обзоре:

- Установщик NemoClaw **не пинится по хэшу**, а тег `lkg` подвижный ([03](for-human/03-nemoclaw.md)).
- В npm лежит **неофициальный пакет `hermes-agent`** от постороннего мейнтейнера ([04](for-human/04-hermes.md)).
- У Ouroboros **нет файла LICENSE**, хотя в README висит бейдж MIT ([05](for-human/05-ouroboros.md)).
- Защитный слой Ouroboros **fail-open именно на локальных моделях** ([05](for-human/05-ouroboros.md)).
- Песочница у OpenClaw **по умолчанию выключена** ([06](for-human/06-openclaw.md)).
- У Perplexity **нет API навыков** — проверено по исчерпывающему индексу документации,
  а не по отсутствию упоминаний ([07](for-human/07-skills-migration.md)).
- Навыки **переносятся между всеми пятью агентами без переписывания**: общий формат
  `SKILL.md`, у Hermes и OpenClaw — заявленный стандарт [agentskills.io](https://agentskills.io/specification)
  ([07](for-human/07-skills-migration.md)).
- **На GB10 MoE-модель на 120B работает вчетверо быстрее плотной на 32B** — 41 против
  9.4 tok/s по [официальным замерам Ollama](https://ollama.com/blog/nvidia-spark-performance).
  Узкое место — пропускная способность памяти (273 ГБ/с), а не её объём ([00](for-human/00-ollama.md)).
- `Memory-Usage: Not Supported` в `nvidia-smi` на GB10 — **штатное поведение**, а не
  поломка: у чипа нет выделенного фреймбуфера. Так и
  [задокументировано NVIDIA](https://docs.nvidia.com/dgx/dgx-spark/known-issues.html) ([00](for-human/00-ollama.md)).
- **У vLLM на DGX Spark `gpu_memory_utilization` не является жёсткой границей** — открытый
  [#46307](https://github.com/vllm-project/vllm/issues/46307) вешает хост целиком, «SSH dies;
  the machine requires a hard power-cycle». На единой памяти отказ забирает ОС, а не процесс
  ([08](for-human/08-vllm-vs-ollama.md)).
- Колёса vLLM `+cu129` для aarch64 **намеренно не содержат sm_121** — то есть GB10. Нужен
  дефолтный тег без суффикса (сборка CUDA 13); `+cu130` не существует
  ([08](for-human/08-vllm-vs-ollama.md)).

## Предупреждение

Все проекты в этом списке, кроме Claude Code и Ollama, — **экспериментальный софт**.
NemoClaw это официальная alpha (`0.1.0`), Ouroboros — исследовательский проект одного автора.
Они выполняют произвольные команды на твоей машине и работают в фоне, когда ты не смотришь.
Раздел «Риски» в каждой инструкции написан не для галочки — прочитай его до установки, а не после.
