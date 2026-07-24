# 15. LM Studio на DGX Spark — и когда он лучше Ollama

LM Studio официально поддерживает DGX Spark с октября 2025
([анонс](https://lmstudio.ai/blog/dgx-spark)) — у него есть сборка для Linux ARM64 и движок
llama.cpp под CUDA 13. Для сервера без монитора ставится не привычное GUI-приложение, а
**llmster** — официальный «безголовый» демон, которым управляет команда `lms`. Именно так
рекомендует делать и [плейбук NVIDIA для Spark](https://github.com/NVIDIA/dgx-spark-playbooks/tree/main/nvidia/lm-studio).

Весь ресерч с первоисточниками и проверкой каждого факта —
[research/lm-studio-vs-ollama-dgx.md](../research/lm-studio-vs-ollama-dgx.md).

## Главное решение: Ollama или LM Studio?

Коротко: **менять Ollama на LM Studio не нужно. Это дополнение, а не замена.**

| Вопрос | Ollama ([тема 00](00-ollama.md)) | LM Studio (llmster) |
|---|---|---|
| Claude Code напрямую | ✅ есть Anthropic-API `/v1/messages` | ❌ **нет** — только OpenAI-формат |
| Hermes, Ouroboros и другие OpenAI-клиенты | ✅ | ✅ |
| Открытость | ✅ [MIT](https://github.com/ollama/ollama/blob/main/LICENSE) | приложение проприетарное, [бесплатно и для работы](https://lmstudio.ai/blog/free-for-work); нельзя только перепродавать как сервис |
| Скачивание моделей из РФ | реестр за Cloudflare → нужен прокси ([тема 00, Шаг 5](00-ollama.md)) | huggingface.co; зеркала для CLI **не поддержаны**, встроенный HF-прокси включается только из GUI |
| Тонкая настройка (выбор кванта, Flash Attention, квантизация KV-кэша, спекулятивное декодирование) | почти нет (грубые серверные переменные) | ✅ богаче, но часть — только через GUI |
| Замеры скорости на Spark | [есть официальные](https://ollama.com/blog/nvidia-spark-performance) | **опубликованных нет ни у кого** — мерить самому |
| Свежие GB10-грабли | [#16610](https://github.com/ollama/ollama/issues/16610): чередование двух тегов одной модели → вечные перезагрузки | ложные CUDA-OOM из-за unified memory → сброс кэша (`echo 3 > drop_caches`, [плейбук NVIDIA](https://github.com/NVIDIA/dgx-spark-playbooks/tree/main/nvidia/lm-studio)) |

Когда LM Studio имеет смысл: (1) хочется покрутить кванты и настройки, которых нет в Ollama;
(2) нужен второй независимый OpenAI-сервер рядом с Ollama (они не мешают друг другу: порты
1234 и 11434); (3) сравнить скорость одних и тех же GGUF на двух движках.

## Установка (одна команда)

```bash
cd ~/dgx-setup && git pull
bash scripts/install-lm-studio.sh
```

Скрипт сам проверит архитектуру, драйвер, `libatomic1`, поставит llmster, поднимет демон и
API-сервер на `http://127.0.0.1:1234/v1`, и прогонит смоук-тест.

Полезные варианты:

```bash
bash scripts/install-lm-studio.sh --model openai/gpt-oss-20b   # сразу скачать и держать модель
bash scripts/install-lm-studio.sh --proxy https://адрес        # если скачивание виснет (Cloudflare)
bash scripts/install-lm-studio.sh --autostart                  # автозапуск при перезагрузке
bash scripts/install-lm-studio.sh --lan                        # открыть в локальную сеть (осознанно!)
bash scripts/install-lm-studio.sh --remove                     # убрать (модели остаются)
```

⚠️ Установщик и модели едут через Cloudflare/HuggingFace — из российской сети скачивание может
повиснуть точно так же, как модели Ollama ([тема 00, Шаг 5](00-ollama.md)). Лекарство то же:
`--proxy` с адресом твоего прокси.

## Повседневные команды

```bash
~/.lmstudio/bin/lms get <модель>            # скачать (можно выбрать квант: имя@q4_k_m)
~/.lmstudio/bin/lms load <модель> --yes     # загрузить в память (останется навсегда)
~/.lmstudio/bin/lms ps                      # что загружено
~/.lmstudio/bin/lms ls                      # что скачано
~/.lmstudio/bin/lms unload --all            # выгрузить всё
~/.lmstudio/bin/lms log stream              # живые логи
```

После перелогина `lms` попадёт в PATH и префикс `~/.lmstudio/bin/` не понадобится.

Какие модели брать — **те же, что для Ollama**: на Spark решает тип весов (MoE), а не размер,
см. [матрицу в теме 00](00-ollama.md). Проверенный старт — `openai/gpt-oss-20b`.
Импорт уже скачанных GGUF (чтобы не качать дважды): `lms import <путь к .gguf>`.

## Что стоит знать честно

- **Claude Code к LM Studio напрямую не подключается** — у него нет Anthropic-API. Локальный
  Claude Code остаётся на Ollama ([тема 01](01-claude-code-local.md)).
- **Скорость обещать нельзя**: опубликованных замеров LM Studio на Spark нет. Движок тот же
  llama.cpp, так что ожидания — на уровне Ollama или чуть быстрее, но проверяется только
  замером на месте (сравни `curl`-запросом одну и ту же модель на 1234 и 11434).
- **Ложный «CUDA out of memory»**: unified memory на Spark иногда «занята» файловым кэшем.
  [Плейбук NVIDIA](https://github.com/NVIDIA/dgx-spark-playbooks/tree/main/nvidia/lm-studio)
  советует: `sudo sh -c 'sync; echo 3 > /proc/sys/vm/drop_caches'` — то же, что мы уже знаем
  по Ollama ([тема 00, Шаг П3](00-ollama.md)).
- **Проприетарность**: сам демон закрыт (открыт только CLI). Бесплатно для дома и работы,
  но это условия вендора, а не свобода MIT — если это принципиально, Ollama остаётся выбором
  по умолчанию.

Рецепт для ИИ-агента: [for-ai/15-lm-studio.md](../for-ai/15-lm-studio.md).
