# 10. Bootstrap: чистый DGX → Claude Code через прокси в КЗ + учёт (рецепт)

Цель: на свежем DGX (aarch64) поднять Claude Code, который ходит в Anthropic/OpenAI **через
VLESS-туннель в Казахстан**, с учётом токенов и стоимости в LiteLLM.

Готовый скрипт делает это целиком: [`scripts/dgx-claude-bootstrap.sh`](../scripts/dgx-claude-bootstrap.sh).
Твоя задача — запустить его и проверить результат, **а не переписывать под себя**. Ниже —
что он делает, чего делать нельзя, и как убедиться, что цепочка собрана.

Целевая цепочка:

```
Claude Code ──ANTHROPIC_BASE_URL=http://127.0.0.1:4000──> LiteLLM :4000
LiteLLM ──HTTPS_PROXY=http://127.0.0.1:10809──> xray-клиент ──VLESS──> VPS(KZ) ──> API
```

---

## П0. Стоп-условия — прочитать до первой команды

1. **Не выдумывать `vless://` ссылку и не подставлять её из примеров.** В ней UUID сервера
   пользователя. Её вводит человек (скрыто, `read -s`). Если ссылки нет — остановись и
   попроси её, не генерируй.
2. **Никаких секретов в git, логи, чат.** Ссылка, ключи Anthropic/OpenAI, master-key,
   пароль БД живут только в `~/.dgx-claude/secrets.env` (chmod 600) и `xray.json` (600).
   Ни один из этих файлов не коммитить и не печатать.
3. **География (см. [09](09-proxy-accounting.md), «Предусловие»).** Правомерно, только если
   И страна DGX, И страна прокси есть в списках поддерживаемых у обоих провайдеров. Скрипт —
   про маршрутизацию через свою инфраструктуру, **не** про обход страновых запретов. Не
   предлагать это как способ работать из неподдерживаемой страны.
4. **В окружении Claude Code НЕ ставить `HTTPS_PROXY`.** Выход Claude Code — это LiteLLM
   (через `ANTHROPIC_BASE_URL`), а уже LiteLLM уходит в туннель. LiteLLM — API-шлюз, а не
   forward-прокси; `HTTPS_PROXY=…:4000` для Claude Code — ошибка. Скрипт специально удаляет
   `HTTPS_PROXY`/`HTTP_PROXY` из `env` в `settings.json`.
5. **Установщик Claude Code гео-блокируется — его скрипт тянет ЧЕРЕЗ ТУННЕЛЬ.** `claude.com`
   в ряде регионов отдаёт HTML «App unavailable in region» (HTTP 200!) вместо `install.sh`;
   запуск такого = «синтаксическая ошибка рядом с `<`». Поэтому фаза Claude качает установщик
   и бинарь через прокси `127.0.0.1:$HTTP_PORT` и проверяет, что скачан скрипт, а не HTML
   (проверено на живом DGX 2026-07-24). Прочие реестры (GitHub, ghcr.io) гео не блокируют —
   их через КЗ гнать не нужно; их режет только российский DPI за Cloudflare (тогда — из
   открытой сети).

---

## П1. Запуск

```bash
git clone https://github.com/djd1m/dgx-setup.git && cd dgx-setup
bash scripts/dgx-claude-bootstrap.sh --diagnose   # сухой прогон
bash scripts/dgx-claude-bootstrap.sh              # полный
```

Предусловия окружения, которые скрипт проверяет, но не чинит сам:
- `uname -m` = `aarch64` (на x86 предупредит и пойдёт, но это не GB10);
- Docker Engine для aarch64 установлен и доступен (`docker ps` без sudo, либо рабочий `sudo`);
- открыт доступ к GitHub / ghcr.io / downloads.claude.ai **на время установки**.

---

## П2. Что делает каждая фаза (и как проверить руками, если упала)

| Фаза | Действие | Ручная проверка при сбое |
|---|---|---|
| 0 диагностика | читает арх/порты/достижимость, ничего не меняет | — |
| 1 xray | скачивает xray `v26.3.27` **с проверкой SHA256**, `vless2xray.py` → `xray.json` (600), `systemd --user` unit, проверка выхода `= KZ` | `xray run -test -c ~/.dgx-claude/xray.json`; `journalctl --user -u dgx-xray` |
| 2 claude | `claude.ai/install.sh`, иначе `npm i -g @anthropic-ai/claude-code` | `claude --version` |
| 3 litellm | `docker compose` (litellm:v1.92.0 + postgres:16), генерит master-key и пароль БД, `HTTPS_PROXY` контейнера → туннель | `docker logs dgx-litellm`; `curl :4000/health/liveliness` |
| 4 configure | пишет `~/.claude/settings.json` → `env`: `ANTHROPIC_BASE_URL`, `ANTHROPIC_AUTH_TOKEN`, `NO_PROXY`; удаляет `HTTPS_PROXY` | `python3 -c "import json;print(json.load(open('$HOME/.claude/settings.json'))['env'])"` |
| 5 verify | KZ-выход + LiteLLM живой + **живой `/v1/messages` = HTTP 200** | см. ниже |

**`vless2xray.py`** проверен на четырёх типах транспорта (`xhttp`/`reality`/`ws`/`grpc`) —
конфиг проходит `xray run -test`. HTTP-inbound поднимается на `127.0.0.1:10809`, SOCKS на
`10808`. Claude Code [SOCKS не умеет](https://code.claude.com/docs/en/network-config) — но
Claude Code сюда и не ходит; в туннель идёт LiteLLM, и он берёт HTTP-порт.

---

## П3. Критерии готовности (это и есть verify-фаза)

Все три обязаны пройти; они написаны так, чтобы **реально падать**, а не печатать «ок»:

1. `curl -x http://127.0.0.1:10809 https://ipinfo.io/country` → `KZ`.
2. `curl http://127.0.0.1:4000/health/liveliness` → 200.
3. Живой round-trip через всю цепочку:
   ```bash
   curl -sS -o /dev/null -w '%{http_code}\n' http://127.0.0.1:4000/v1/messages \
     -H "x-api-key: $LITELLM_MASTER_KEY" -H "anthropic-version: 2023-06-01" \
     -H "content-type: application/json" \
     -d '{"model":"<model_name из конфига>","max_tokens":8,"messages":[{"role":"user","content":"ping"}]}'
   ```
   Ждём `200`. Не-200 — цепочка собрана не до конца; тело ответа скажет, где.

**Ground truth, который проверяется только на стороне пользователя:** во время запроса
**растут счётчики байт в x-ui на VPS**. Это единственное прямое доказательство, что LiteLLM
ушёл в туннель, а не напрямую. Anthropic примет запрос и из Амстердама (тоже поддерживаемая
страна), так что по одному лишь HTTP 200 факт прохождения через КЗ **не доказывается** —
попроси пользователя глянуть счётчики.

---

## Что осталось непроверенным

- **Уважает ли LiteLLM `HTTPS_PROXY` для исходящих в конкретной версии.** По умолчанию
  `httpx` его читает (`trust_env=True`), но это надо подтвердить счётчиками x-ui, а не
  предполагать. **NOT VERIFIED** на уровне «гарантированно во всех версиях».
- **Что образ `litellm:v1.92.0` штатно стартует именно на GB10.** arm64-манифест у образа
  есть (проверено), но живой старт на этом железе — нет. Если контейнер падает —
  `docker logs dgx-litellm`.
- **Точные id моделей** в шаблоне конфига — placeholder. Свериться со списками провайдеров.
- **Что у пользователя на VPS именно VLESS.** Скрипт исходит из этого. Если там HTTP-прокси —
  `--skip-xray` и настройка по [09, Вариант A/C](09-proxy-accounting.md); туннель не нужен.
- **`downloads.claude.ai` с этой машины** — если недоступен, откат на `npm` (должен быть в системе).
