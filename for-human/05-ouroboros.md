# 05. Ouroboros — самомодифицирующийся агент

Требуется: выполненная инструкция [00-ollama.md](00-ollama.md).

Репозиторий: [github.com/razzant/ouroboros](https://github.com/razzant/ouroboros).
Проверено на коммите `554b3ee`, версия **6.64.1**.

## Что это

Не кодинг-ассистент. Дословно из [README](https://github.com/razzant/ouroboros/blob/main/README.md):

> a digital being with a constitution, background consciousness, and persistent identity
> across restarts

Агент **читает и переписывает собственный исходный код**, ведёт свой git-репозиторий и
крутит фоновый цикл «сознания» между задачами. Управляется «конституцией» из 13 принципов
в файле [`BIBLE.md`](https://github.com/razzant/ouroboros/blob/main/BIBLE.md).

Приятный факт: автор — Антон Разжигаев, россиянин. Из коробки поддержаны **GigaChat** и
**Cloud.ru** — такого нет больше ни у одного агента в этом списке.

---

## Ты выбрал правильный репозиторий

Под именем «ouroboros» на GitHub лежит несколько проектов. Проверено через GitHub API:

| Репозиторий | Форк? | Звёзды | Последний коммит |
|---|---|---|---|
| **razzant/ouroboros** | **нет — это оригинал** | 716 | 2026-07-16 |
| joi-lab/ouroboros | да, форк razzant | 897 | 2026-07-14 |
| AntonAndrusenko/ouroboros-max | да, форк razzant | 0 | 2026-03-16, заброшен |
| oseledets/ouroboros | копия, заморожена | 1 | 2026-02-18 |

У `joi-lab` больше звёзд, но это **зеркало** — его собственное описание гласит:
*«Active mirror of https://github.com/razzant/ouroboros — open issues and PRs there»*.
История коммитов совпадает по SHA. Звёзды не делают форк первоисточником.

---

## ⚠️ Три вещи, которые надо знать до установки

### 1. У проекта нет лицензии

В README висит бейдж MIT со ссылкой на `LICENSE`. **Файла `LICENSE` в репозитории нет.**
GitHub API отдаёт `"license": null`.

Юридически отсутствие лицензии означает **«все права защищены»** — формально прав
использовать этот код у тебя нет. Скорее всего, автор просто забыл положить файл. Но по
состоянию на сейчас бейдж ничем не подкреплён.

*(Форки joi-lab и AntonAndrusenko показывают MIT в API — но форк не может выдать лицензию,
которой не дал оригинал.)*

### 2. Это исследовательский проект одного человека

Звёзды обманывают. Реальные цифры:

| Показатель | Значение |
|---|---|
| Звёзд | 716 |
| **Скачиваний Linux-сборки v6.64.1** | **2** |
| Скачиваний Windows | 17 |
| Скачиваний macOS | 13 |
| Автор | 56 из последних коммитов — один человек |

Релизы идут очень быстро: три коммита `release: v6.64.0` за 27 минут, следом хотфикс.
Это **экспериментальный софт**, а не продукт.

### 3. Защита отключается сама именно на локальных моделях

Об этом — отдельный раздел ниже. Прочитай его.

---

## Шаг 1. Установка из исходников

**Требуется:** Python **3.10+**, Git. Node, Rust и Docker для этого пути не нужны.

Дословно из [README](https://github.com/razzant/ouroboros/blob/main/README.md), **плюс одна
строка от меня** — про неё сразу после:

```bash
git clone https://github.com/razzant/ouroboros.git
cd ouroboros
git checkout 554b3ee          # ← этой строки в README нет, но она нужна
python3.11 -m venv .venv
source .venv/bin/activate
python -m pip install --upgrade pip setuptools wheel
python -m pip install -r requirements.txt
python -m pip install -e . --no-deps
```

> ⚠️ **Зачем `git checkout 554b3ee`.** Вся эта инструкция — включая находки про
> [fail-open защиты](#3-защита-отключается-сама-именно-на-локальных-моделях) и отсутствие
> LICENSE — проверена **на этом коммите**. `git clone` без него даст тебе `main`, который
> с тех пор уехал. Это агент, который **переписывает собственный код**; читать про одну
> версию, а запускать другую — плохая идея именно здесь.
>
> Хочешь свежий `main` — твоё право, но тогда находки ниже нужно перепроверять заново,
> а не считать проверенными.

Запуск:

```bash
ouroboros server
```

Открывается на `http://127.0.0.1:8765`.

### 🚫 Не качай десктопную сборку

`Ouroboros-linux.tar.gz` весит **902 МБ** и запускает оболочку на PyWebView, которой нужен
монитор. На DGX без графики она не заработает.

**`ouroboros server` — полностью headless, X11 не нужен.** Проверено тремя способами:

- Флаг `--no-ui` в `cli.py:454` — **пустышка**, его собственная справка гласит:
  *«accepted for CLI parity; server mode has no desktop UI»*.
- `pywebview` импортируется **только** в `launcher.py`. В `server.py` его нет.
- `pywebview` вообще **отсутствует в `requirements.txt`** — установка из исходников
  графический стек не тянет.

### Доступ по сети

Сервер слушает `127.0.0.1`. Правильный способ достучаться с ноутбука — SSH-туннель:

```bash
ssh -L 8765:127.0.0.1:8765 пользователь@адрес-dgx
```

Если всё-таки открываешь наружу — обязательно задай `OUROBOROS_NETWORK_PASSWORD`,
иначе не-loopback привязка заблокирована.

---

## Шаг 2. Подключить Ollama

### 🚫 Сначала — чего делать НЕ надо

У Ouroboros есть встроенная поддержка локальных моделей через llama-cpp-python (GGUF).
**На Linux она работает только на процессоре.** Доказательства:

- README ограничивает ускорение: *«Metal acceleration on Apple Silicon, **CPU on Linux/Windows**»*
- `LOCAL_MODEL_N_GPU_LAYERS` по умолчанию **`0`** (`config.py:299`) — то есть ноль слоёв на GPU
- В `requirements.txt` подсказка сборки только под Metal
- **Во всём репозитории нет ни одного упоминания CUDA**

Пойдёшь этим путём — твои GPU будут простаивать, а модель считаться на CPU.

*(Заработает ли llama-cpp-python, собранный с CUDA, вместе с `LOCAL_MODEL_N_GPU_LAYERS=-1` —
**NOT VERIFIED**. Правдоподобно, но авторами не документировано и не проверялось.)*

### ✅ Как надо — через OpenAI-совместимый провайдер

В README слова «Ollama» нет, но в исходниках она есть.
`ouroboros/settings_setup_contract.py:59`, дословно:

```
("openai-compatible-url", "compatibleBaseUrl", "OPENAI_COMPATIBLE_BASE_URL", "s-compatible-url",
 "OpenAI-compatible Base URL", "http://localhost:11434/v1",
 "Base URL for your OpenAI-compatible endpoint (e.g. Ollama, LM Studio, vLLM). ...", "url"),
```

Плейсхолдер — буквально порт Ollama **11434**. Настройка через страницу Settings или `settings.json`:

| Параметр | Значение |
|---|---|
| `OPENAI_COMPATIBLE_BASE_URL` | `http://localhost:11434/v1` |
| `OPENAI_COMPATIBLE_API_KEY` | **оставить пустым** |

Дальше — важное: **каждый слот модели** нужно заполнить вручную в виде
`openai-compatible::имя-модели`. Например `openai-compatible::qwen3.6:27b`.

Из того же файла: *«Use openai-compatible::your-model-name for every slot. The model list
is whatever your server supports»*. Значения по умолчанию для произвольного эндпоинта нет —
пустой слот работать не будет.

Если оставить как есть, по умолчанию используется `google/gemini-3.5-flash` через OpenRouter —
из России это не заработает.

---

## 🚨 Шаг 3. Безопасность — читать обязательно

Напомню, что это за программа: **агент, который переписывает собственный код, сам запускает
shell-команды, ставит пакеты и работает в фоне, когда ты не смотришь.**

### Как устроена защита

**Слой 1 — детерминированная песочница** (всегда включена). `runtime_mode_policy.py:16`,
полный список защищённых файлов:

```python
SAFETY_CRITICAL_PATHS = frozenset({
    "BIBLE.md", "ouroboros/safety.py", "ouroboros/runtime_mode_policy.py",
    "ouroboros/tools/extension_dispatch.py", "ouroboros/tools/registry.py", "prompts/SAFETY.md",
})
```

**Слой 2 — LLM-надзиратель**: на каждый вызов инструмента спрашивает лёгкую модель,
безопасно ли это.

### Где здесь дыры

**1. Защитный промпт написан максимально снисходительным.**
[`prompts/SAFETY.md`](https://github.com/razzant/ouroboros/blob/main/prompts/SAFETY.md)
открывается словами:

> Block ONLY clearly destructive or exfiltrating actions. **Default to SAFE.**

и заканчивается:

> **When in doubt → SAFE.** Only DANGEROUS when clearly and unambiguously harmful to the system.

Явно разрешены: удаление обычных файлов в папке проекта, `curl`/`wget`, `pip install`.

**2. Вердикт `SUSPICIOUS` ничего не блокирует.** `safety.py` возвращает «разрешено» и лишь
печатает: *«The command was allowed, but consider whether this is the right approach»*.

**3. 🔥 На локальных моделях защита fail-open.** Это прямо про твою конфигурацию.
`safety.py:678–693`: если локальный движок безопасности недоступен — **команда пропускается**:

```
# Fallback local outage warns instead of blocking all unknown tools
return True, "⚠️ SAFETY_WARNING: Local safety runtime unreachable ..."
```

Для облачных провайдеров при сбое — наоборот, **запрет** (`return False`). А для локальных —
разрешение. То есть **Ollama икнула → LLM-слой защиты молча выключился**. Остаётся только
список из шести файлов выше.

Хуже: `safety.py:600–606` — если модель безопасности не настроена вовсе, проверка
**пропускается целиком**.

**4. Промпт думает, что он на макбуке.** Открывается словами
*«an autonomous AI agent running on a user's Mac»*. На Linux он судит с неверной моделью мира.

**5. Главное — что именно он защищает.** Песочница бережёт **файлы самого Ouroboros**.
Её волнует, чтобы агент не ослабил собственное управление. Всё остальное — твой домашний
каталог, твой DGX — прикрыто только снисходительным «Default to SAFE».

### Вывод: запускай в Docker

В репозитории есть `Dockerfile` (`FROM python:3.10-slim`, `ENTRYPOINT ["python", "server.py"]`).
**На общей машине уровня DGX запускай Ouroboros в контейнере, а не голым.**

Аварийная остановка — команда **`/panic`** в чате: *«Emergency stop. Kills ALL processes»*.
Запомни её до того, как понадобится.

---

## Дополнительно

Библиотеки для браузерных инструментов (нужен sudo, необязательно):

```bash
python3 -m playwright install-deps chromium webkit
```

**Про Hugging Face.** `huggingface_hub` — жёсткая зависимость, а встроенные пресеты
локальных моделей тянут GGUF прямо с HF, который из России работает нестабильно.
**Путь через Ollama эту проблему обходит** — модели ты качаешь через `ollama pull`.

---

## Готово, если

- [ ] `ouroboros server` стартует без ошибок
- [ ] `http://127.0.0.1:8765` открывается (через SSH-туннель)
- [ ] в Settings стоит `OPENAI_COMPATIBLE_BASE_URL=http://localhost:11434/v1`
- [ ] **все** слоты моделей заполнены как `openai-compatible::...`
- [ ] агент отвечает, и в `nvidia-smi` видна нагрузка
- [ ] ты знаешь про `/panic`
- [ ] ты прочитал раздел про безопасность целиком, а не пролистал
