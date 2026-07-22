# 11. Три агента на одном хосте без взаимных помех — рецепт

Цель: на DGX, где **Hermes уже на хосте** (не в контейнере), добавить
[Ouroboros](05-ouroboros.md) и [OpenClaw](06-openclaw.md) так, чтобы три фоновых агента не
конфликтовали по портам/каталогам/сервисам/Ollama и не читали секреты друг друга.

Сверено по исходникам: Ouroboros [`554b3ee`](https://github.com/razzant/ouroboros/tree/554b3ee),
OpenClaw и Hermes `main`, [Ollama](https://github.com/ollama/ollama) `main`. Непроверенное — **NOT VERIFIED**.

## Вывод: по умолчанию коллизий НЕТ. Работать надо над безопасностью.

## Карта портов (коллизий по умолчанию нет)

| Агент | Порт | Всегда? | Переопределить |
|---|---|---|---|
| Ouroboros | `8765` сервер | да (авто-сдвиг 8765–8774 если занят) | `OUROBOROS_SERVER_PORT` |
| Ouroboros | `8767` host-service | да | `OUROBOROS_HOST_SERVICE_PORT` |
| Ouroboros | `8766` llama-cpp | только при `USE_LOCAL_*=True` | `LOCAL_MODEL_PORT` |
| OpenClaw | `18789` WS+HTTP+Control UI | да | `gateway.port` / `--port` |
| Hermes | `8642` API-шлюз | да | `API_SERVER_PORT` |
| Hermes | `9119` дашборд | только при `hermes web` | `hermes web --port` |
| Hermes | `8644` webhook | только при webhook-платформе | webhook port |
| (общий) | `11434` Ollama | потребляют все | `OLLAMA_HOST` |

Все различны → действий не требуется, пока не поднимаешь **второй** экземпляр того же агента.

## Карта каталогов (не пересекаются) + перенос

| Агент | Каталог | Перенести целиком |
|---|---|---|
| Ouroboros | `~/Ouroboros/` (**не** `~/.ouroboros`) | `OUROBOROS_APP_ROOT` |
| OpenClaw | `~/.openclaw/` | `OPENCLAW_HOME` (multi: `OPENCLAW_PROFILE`) |
| Hermes | `~/.hermes/` | `HERMES_HOME` |

## Сервисы (имена не совпадают)

- Hermes: `hermes-gateway.service` (systemd `--user` или system).
- OpenClaw: `openclaw-gateway.service` (`onboard --install-daemon` → systemd `--user`; linger уже ставит).
- **Ouroboros: установщика НЕТ** — пиши свой `--user`-юнит на `ouroboros server`. Фон = потоки
  в процессе, не демон ОС.

## Ollama — единственная реальная интерференция

Рычаги ([envconfig](https://github.com/ollama/ollama/blob/main/envconfig/config.go)):
`OLLAMA_KEEP_ALIVE` (деф. 5m; `-1` = ∞), `OLLAMA_MAX_LOADED_MODELS` (деф. **`0`=auto**, не 3),
`OLLAMA_NUM_PARALLEL` (деф. 1).

- **Разные модели у агентов → thrashing** (перезагрузка при каждом переключении).
- **Решение по умолчанию: одна общая модель на всех троих.** Нужны разные — `MAX_LOADED_MODELS=3`
  + `KEEP_ALIVE=-1` + проверить, что 119 ГБ держат их разом ([Матрица](00-ollama.md), тремя MoE — да).
- 🛑 [#14621](https://github.com/ollama/ollama/issues/14621): параллельные запросы могут ронять
  Ollama (SIGABRT). Держи `OLLAMA_NUM_PARALLEL` умеренным.

**Кто как ходит в Ollama (важно, легко перепутать):**
- OpenClaw — `http://127.0.0.1:11434` **без** `/v1` (нативный API).
- Ouroboros — по умолчанию **НЕ Ollama** (llama-cpp на 8766); включается `OPENAI_COMPATIBLE_BASE_URL=http://localhost:11434/v1` (**с** `/v1`).
- Hermes — через OpenAI-совместимый транспорт, base_url **с** `/v1`.

## 🛑 Безопасность — почему нельзя всех под одним пользователем

Каждый агент исполняет произвольные команды в фоне. Два подтверждённых факта:
- OpenClaw: [*«Sandboxing is off by default»*](https://docs.openclaw.ai/gateway/sandboxing) —
  исполнение инструментов на хосте без песочницы.
- Ouroboros: защитный слой **fail-open на локальных провайдерах** (`safety.py` на
  [`554b3ee`](https://github.com/razzant/ouroboros/tree/554b3ee): недоступен локальный safety-LLM
  → вызов **разрешён**).

Под одним пользователем → любой агент читает `~/.hermes/.env`, `~/.openclaw/openclaw.json`, `~/Ouroboros`.

## Рекомендованная раскладка

1. **Отдельный OS-пользователь на агента** (`ouro`/`openclaw`/`hermes`). Для boot-автозапуска
   `--user`-юнитов: `loginctl enable-linger <user>`.
2. Порты не трогать (дефолты не сталкиваются).
3. Ollama — один хостовый сервис, **одна модель на всех** (или подними лимиты + проверь память).
4. Сервисы: `hermes-gateway` и `openclaw-gateway` — `--user`-юнитами своих пользователей;
   Ouroboros — свой `--user`-юнит.
5. **Свой venv** на Python-агента (Ouroboros/Hermes), **свой npm-prefix** на OpenClaw.
6. Каталоги при желании закрепить явно (`OUROBOROS_APP_ROOT`/`OPENCLAW_HOME`/`HERMES_HOME`).

Строже: **контейнеры только для двух новых**, Hermes на хосте; они ходят в хостовый Ollama через
`host.docker.internal:11434`.

## Критерий готовности

```bash
# порты слушают три РАЗНЫХ процесса, без коллизий
ss -tlnp | grep -E ':(8765|8767|18789|8642|11434)\b'
# сервисы разных пользователей
systemctl --user list-units 'hermes-gateway*' 'openclaw-gateway*' 2>/dev/null
# ни один агент не читает чужой .env (проверять от лица КАЖДОГО пользователя)
sudo -u openclaw cat /home/hermes/.hermes/.env 2>&1 | grep -q 'Permission denied' && echo "ISOLATION_OK"
```

## Стоп-условия / поправки

- Переменные Ouroboros — **`OUROBOROS_SERVER_PORT`** / **`OUROBOROS_APP_ROOT`** (НЕ `OURO_PORT`/`OURO_DIR`).
- Ouroboros по умолчанию НЕ в Ollama (llama-cpp:8766) — не считать обратное.
- **NOT VERIFIED:** `OLLAMA_MAX_LOADED_MODELS` дефолт `0` — из
  [envconfig](https://github.com/ollama/ollama/blob/main/envconfig/config.go), версии меняются;
  глобальные npm/Python-пакеты как канал связывания — риск реальный, по исходникам детально не прослежен.
