# 01. Claude Code на локальной Ollama

Claude Code — кодинг-агент в терминале. Обычно он ходит на серверы Anthropic, но у Ollama
есть **Anthropic-совместимый эндпоинт**, и Claude Code можно направить прямо в него —
на твою же машину.

Требуется: выполненная инструкция [00-ollama.md](00-ollama.md).

## Что это даёт

```
Claude Code  ──/v1/messages──>  Ollama на localhost:11434  ──>  твои GPU
```

- **Аккаунт Anthropic не нужен.** Вообще. Ни подписки, ни логина, ни ключа.
- **Ни одного запроса на серверы Anthropic.** Всё остаётся на DGX.
- Модель — любая из тех, что ты скачал в инструкции 00.

Это не самоделка: интеграция **официально описана в репозитории Ollama** —
[docs/integrations/claude-code.mdx](https://github.com/ollama/ollama/blob/main/docs/integrations/claude-code.mdx).

---

## Шаг 1. Установить Claude Code

```bash
curl -fsSL https://claude.ai/install.sh | bash
```

Официальный способ — [Advanced setup](https://code.claude.com/docs/en/setup).

**Если не скачивается.** Это ресурс Anthropic, и из России он может быть недоступен.
*(Достоверно проверить из российской сети я не мог — **NOT VERIFIED**.)* Anthropic сама
документирует альтернативу через npm, и npm из России работает:

```bash
npm install -g @anthropic-ai/claude-code
```

Нужен Node.js 22 или новее. Пакет ставит **тот же самый бинарник**, что и скрипт.

> ⚠️ **`sudo npm install -g` не используй** — это прямое предупреждение из документации
> Anthropic: приводит к проблемам с правами и рискам безопасности.

Проверка:

```bash
claude --version
```

---

## Шаг 2. Направить Claude Code в Ollama

```bash
export ANTHROPIC_AUTH_TOKEN=ollama
export ANTHROPIC_API_KEY=""
export ANTHROPIC_BASE_URL=http://localhost:11434
```

Дословно из [документации Ollama](https://github.com/ollama/ollama/blob/main/docs/integrations/claude-code.mdx).

Разберём, что здесь происходит:

| Переменная | Смысл |
|---|---|
| `ANTHROPIC_BASE_URL` | куда слать запросы. Вместо Anthropic — на твою Ollama |
| `ANTHROPIC_AUTH_TOKEN` | Ollama ключ не проверяет, но переменная нужна непустая |
| `ANTHROPIC_API_KEY=""` | **пустой намеренно** — именно это отключает поход в Anthropic |

Чтобы не вводить каждый раз, добавь в `~/.bashrc`:

```bash
echo 'export ANTHROPIC_AUTH_TOKEN=ollama' >> ~/.bashrc
echo 'export ANTHROPIC_API_KEY=""' >> ~/.bashrc
echo 'export ANTHROPIC_BASE_URL=http://localhost:11434' >> ~/.bashrc
source ~/.bashrc
```

Выбрать модель:

```bash
export ANTHROPIC_MODEL=qwen3.6:27b
```

Имя должно точно совпадать с тем, что показывает `ollama list`.

---

## Шаг 3. Запустить

```bash
cd ~/твой-проект
claude
```

Либо короткий путь от самой Ollama — она поднимет всё сама:

```bash
ollama launch claude
```

Для скриптов и CI:

```bash
ollama launch claude --model qwen3.6:27b --yes -- -p "твой запрос"
```

Флаг `--yes` пропускает выбор модели и скачивает её, если нужно.

---

## Что работает, а что нет

Ollama реализует Anthropic-протокол не полностью. Честный список из
[anthropic-compatibility.mdx](https://github.com/ollama/ollama/blob/main/docs/api/anthropic-compatibility.mdx):

**Работает:**
сообщения, стриминг, системные промпты, многоходовые диалоги, vision (картинки),
**вызов инструментов (tools)**, результаты инструментов, thinking-блоки.

Вызов инструментов — самое важное: без него агент не сможет читать файлы и запускать команды.

**Не работает:**

| Чего нет | Насколько мешает |
|---|---|
| Prompt caching | заметно: каждый запрос считается заново, медленнее и дороже по времени |
| `tool_choice` | нельзя заставить вызвать конкретный инструмент |
| `/v1/messages/count_tokens` | подсчёт токенов недоступен |
| Batches API | пакетная обработка |
| Citations, PDF | работа с документами |
| Картинки по URL | только base64 |

Плюс две оговорки из доков: подсчёт токенов **приблизительный**, а `budget_tokens`
у thinking **принимается, но не соблюдается**.

---

## Честно о том, чего ждать

**Это не Claude.** Ты запускаешь Qwen или GPT-OSS в оболочке Claude Code. Интерфейс тот же,
модель — другая, и она слабее. Агентный цикл (прочитать файл → подумать → отредактировать →
проверить) требователен к качеству вызова инструментов, и локальные модели тут заметно
уступают. Ожидай больше ошибок и более простых задач.

**Контекст решает.** Если Claude Code ведёт себя странно — теряет нить, забывает файлы —
почти наверняка мало контекста. Проверь, что `OLLAMA_CONTEXT_LENGTH=64000` из инструкции 00
действительно применился:

```bash
ollama ps
```

Смотри колонку `CONTEXT`.

**Про правила Anthropic.** В системных требованиях Claude Code, наравне с ОС и памятью,
указано местоположение — [Advanced setup](https://code.claude.com/docs/en/setup) ссылается
на [список поддерживаемых стран](https://www.anthropic.com/supported-countries), России
в нём нет. В этой конфигурации ты не обращаешься к сервисам Anthropic вообще: программа
работает как локальный клиент к твоей Ollama, и такую связку **официально документирует
сама Ollama**. Тем не менее требование в документации сформулировано общо — знай об этом
и решай сам.

---

## Готово, если

- [ ] `claude --version` печатает версию
- [ ] `echo $ANTHROPIC_BASE_URL` → `http://localhost:11434`
- [ ] `claude` запускается и отвечает на простой вопрос
- [ ] `ollama ps` во время работы показывает загруженную модель
- [ ] в `nvidia-smi` при запросе видна нагрузка на GPU

Проверить связку одной командой, не запуская Claude Code:

```bash
curl -s http://localhost:11434/v1/messages \
  -H "Content-Type: application/json" \
  -d '{"model":"qwen3.6:27b","max_tokens":64,"messages":[{"role":"user","content":"Скажи привет"}]}'
```

Пришёл JSON с ответом — всё сходится.
