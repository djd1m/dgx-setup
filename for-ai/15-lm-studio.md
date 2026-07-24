# 15. LM Studio (llmster, headless) на DGX Spark — рецепт для AI-кодера

**Цель:** поднять LM Studio как headless OpenAI-совместимый сервер на DGX Spark / GB10
(`aarch64`, DGX OS) рядом с Ollama, не мешая ей. Ставится демон **llmster** + CLI **lms**,
НЕ GUI-приложение.

Первоисточники и верификация каждого факта: [research/lm-studio-vs-ollama-dgx.md](../research/lm-studio-vs-ollama-dgx.md).
Ключевые: [анонс DGX Spark](https://lmstudio.ai/blog/dgx-spark) (Linux ARM64 + CUDA 13),
[headless-доки](https://lmstudio.ai/docs/developer/core/headless),
[плейбук NVIDIA](https://github.com/NVIDIA/dgx-spark-playbooks/tree/main/nvidia/lm-studio),
[systemd-рецепт](https://lmstudio.ai/docs/developer/core/headless_llmster).

## 🛑 Прежде чем ставить — проверить, зачем

1. **Для Claude Code этот сервер бесполезен**: у LM Studio НЕТ Anthropic-API `/v1/messages`
   (только OpenAI `/v1/*` + свой `/api/v1/*`). Claude Code локально = Ollama
   ([01-claude-code-local.md](01-claude-code-local.md)). Не предлагать LM Studio как замену.
2. Ollama с [00-ollama.md](00-ollama.md) уже закрывает OpenAI-клиентов. LM Studio ставится
   как **дополнение** (второй движок, тонкие настройки, сравнение скорости), по явному запросу
   человека.

## Предусловия

| Проверка | Ожидаемо | Если не так |
|---|---|---|
| `uname -m` | `aarch64` (или `x86_64`) | **STOP** — других сборок нет |
| `nvidia-smi` → драйвер | ≥ 550 | **STOP** — сначала [00-ollama.md, Шаг П2](00-ollama.md) |
| `ldconfig -p \| grep libatomic.so.1` | есть | `sudo apt-get install -y libatomic1` (без него официальный install.sh отказывается работать) |
| порт 1234 свободен (`ss -ltn`) | свободен | занят → задать другой через `--port` |

`Memory-Usage: Not Supported` в `nvidia-smi` — норма GB10, не чинить ([00-ollama.md, Шаг П3](00-ollama.md)).

## Шаги

### Шаг 1. Установка — скриптом с самодиагностикой

```bash
cd ~/dgx-setup && git pull
bash scripts/install-lm-studio.sh                      # базовая: демон + сервер на 1234
bash scripts/install-lm-studio.sh --model openai/gpt-oss-20b --autostart   # + модель + автозапуск
```

Ожидаемо: `Готово.` и смоук-тест `/v1/models` прошёл.

Если скачивание виснет: артефакты идут с `llmster.lmstudio.ai` / `installers.lmstudio.ai` —
оба за **Cloudflare** (проверено заголовками), из РФ это режется как в
[00-ollama.md, Шаг 5](00-ollama.md). Перезапустить с `--proxy <адрес от человека>`.
🛑 `PROXY` не выдумывать — взять у человека.

Что скрипт делает под капотом (если нужно вручную): официальный
`curl -fsSL https://lmstudio.ai/install.sh | bash` → `~/.lmstudio/bin/lms daemon up` →
`lms server start --bind 127.0.0.1 --port 1234`.

### Шаг 2. Модель

Правила выбора — **те же, что в [00-ollama.md](00-ollama.md)**: на GB10 брать MoE, не плотную;
размер файла ≠ скорость. Имена моделей у LM Studio свои (реестр Hugging Face, не реестр Ollama):

```bash
~/.lmstudio/bin/lms get openai/gpt-oss-20b        # скачать; квант можно указать: имя@q4_k_m
~/.lmstudio/bin/lms load openai/gpt-oss-20b --yes --context-length 64000
```

- `--yes` (не `-y` — короткая форма в доках не подтверждена) — без интерактивных вопросов.
- `--context-length 64000` — минимум для агентов (урок из [00-ollama.md](00-ollama.md): Hermes
  не стартует ниже 64000).
- Загруженная через `lms load` модель живёт в памяти **без TTL** до `lms unload`; модели,
  поднятые JIT-запросом к API, выгружаются после 60 минут простоя
  ([доки TTL](https://lmstudio.ai/docs/developer/core/ttl-and-auto-evict)).
- Уже скачанные для других движков GGUF не качать заново: `lms import <путь.gguf>`.
- Хранилище: `~/.lmstudio/models/<издатель>/<модель>/`.

### Шаг 3. Проверка

```bash
curl -fsS http://127.0.0.1:1234/v1/models | grep '"data"'      # список моделей
curl -s http://127.0.0.1:1234/v1/chat/completions -H 'Content-Type: application/json' \
  -d '{"model":"openai/gpt-oss-20b","max_tokens":16,"messages":[{"role":"user","content":"привет"}]}'
```

Ожидаемо: HTTP 200 и осмысленный `content`. Дальше — обязательный замер скорости и смоук-тест
tool-loop (как Шаг 6b и правило 🛑 из [00-ollama.md](00-ollama.md)): формальный 200 ещё не
значит «пригодно».

### Шаг 4. Автозапуск (по запросу человека)

`bash scripts/install-lm-studio.sh --autostart` — пишет [официальный юнит](https://lmstudio.ai/docs/developer/core/headless_llmster)
в `/etc/systemd/system/lmstudio.service` (`Type=oneshot` + `RemainAfterExit`, абсолютные пути —
systemd не понимает `~`). Проверка: `systemctl status lmstudio.service` после ребута.

## Отличия от Ollama, которые ловят агентов

| | Ollama | LM Studio |
|---|---|---|
| Порт | 11434 | **1234** (⚠️ по докам «последний использованный» — всегда задавать `--port` явно) |
| Anthropic `/v1/messages` | ✅ | ❌ |
| OpenAI `/v1/*` | ✅ (без `logprobs`, `tool_choice`, `logit_bias`, `n`) | ✅ + `/v1/responses`; стейтфул-чат — отдельный `POST /api/v1/chat` |
| Имена моделей | `gpt-oss:20b` (реестр Ollama) | `openai/gpt-oss-20b` (Hugging Face) |
| Держать модель в памяти | `keep_alive`/`OLLAMA_KEEP_ALIVE` | `lms load` (без TTL) vs JIT (60 мин) |
| Параллельность | `OLLAMA_NUM_PARALLEL` (деф. 1) | «Max Concurrent Predictions», деф. 4, с [0.4.0](https://lmstudio.ai/blog/0.4.0) |
| Structured output | `format` (JSON schema) | `response_format: json_schema` |

## Стоп-условия

1. **Не предлагать LM Studio для Claude Code** — нет Anthropic-API, это тупик. Только Ollama.
2. **Не сносить и не останавливать Ollama ради LM Studio** — они сосуществуют (1234 vs 11434).
   Одновременно держать тяжёлые модели в обоих — считать память (`free -g`).
3. **`--lan` / `--bind 0.0.0.0` — только по решению человека**: авторизации у сервера нет
   (то же правило, что для `OLLAMA_HOST` в [00-ollama.md](00-ollama.md)).
4. **Прокси не выдумывать** — адрес берётся у человека ([00-ollama.md, стоп-условие 5](00-ollama.md)).
5. **Скорость не обещать**: опубликованных замеров LM Studio на Spark нет (проверено роем,
   2026-07-24) — только мерить на месте. Установка с непомеренной скоростью ≠ «готово».
6. **Ложный CUDA-OOM при свободной памяти** — не считать нехваткой памяти: сначала
   `sudo sh -c 'sync; echo 3 > /proc/sys/vm/drop_caches'` (воркэраунд из
   [плейбука NVIDIA](https://github.com/NVIDIA/dgx-spark-playbooks/tree/main/nvidia/lm-studio);
   команда меняет состояние системы — по решению человека, как в [00-ollama.md](00-ollama.md)).
7. **GUI/AppImage на сервер не ставить** — 1.34 ГБ бесполезного на SSH-машине; всё делается
   через llmster+lms. Встроенный HF-прокси, увы, включается только из GUI — если он понадобился,
   это вопрос человеку, а не повод ставить AppImage самовольно.

## Критерий готовности

```bash
set -u; FAIL=0
LMS="$HOME/.lmstudio/bin/lms"
[ -x "$LMS" ] && echo "OK 1" || { echo "FAIL 1: нет $LMS"; FAIL=1; }
"$LMS" daemon status >/dev/null 2>&1 && echo "OK 2" || { echo "FAIL 2: демон не отвечает"; FAIL=1; }
curl -fsS -m 10 http://127.0.0.1:1234/v1/models | grep -q '"data"' \
  && echo "OK 3" || { echo "FAIL 3: /v1/models"; FAIL=1; }
"$LMS" ps 2>/dev/null | grep -q . && echo "OK 4 (модель загружена)" || echo "WARN 4: модель не загружена (допустимо, если так задумано)"
[ "$FAIL" -eq 0 ] && echo "ALL CHECKS PASSED" || echo "CHECKS FAILED"
```

Готово полностью, только если вдобавок: (а) замерена скорость генерации и она разумна для
MoE-модели (десятки tok/s, не единицы); (б) смоук-тест tool-loop пройден, если сервер будет
кормить агентов. Формальные проверки этого не ловят — как и в [00-ollama.md](00-ollama.md).
