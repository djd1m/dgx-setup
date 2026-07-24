# 14. Claude Code через Cloud.ru напрямую — без LiteLLM, без docker, без туннеля

Самый простой способ дать Claude Code мозги от Cloud.ru: у Cloud.ru Foundation Models **появился
свой Anthropic-совместимый API** (`/v1/messages`), и Claude Code умеет ходить в него **напрямую**.
Никакого прокси-переводчика, docker или VPN-туннеля.

> Это **отдельная** инструкция, не замена [02-claude-code-cloudru.md](02-claude-code-cloudru.md).
> В 02 стоит LiteLLM-переводчик — он был нужен, потому что раньше у Cloud.ru был только
> OpenAI-формат. **Проверено живьём 2026-07-24: теперь есть и Anthropic-формat** → всё проще.

## Как это работает

```
Claude Code ──Anthropic /v1/messages──> Cloud.ru FM
   ANTHROPIC_BASE_URL=https://foundation-models.api.cloud.ru
   ANTHROPIC_AUTH_TOKEN=<твой ключ Cloud.ru>
   ANTHROPIC_MODEL=<модель>
```

Claude Code шлёт запросы в своём родном формате, Cloud.ru их понимает. Одна команда — `claude-fm`.

## Установка (одна команда)

```bash
cd ~/dgx-setup && git pull                          # подтянуть скрипт
bash scripts/install-claude-fm.sh
```

Скрипт спросит **ключ Cloud.ru** (личный кабинет → сервисный аккаунт → API-ключ; вводится скрыто),
сам проверит связь и подберёт рабочую модель, и создаст команду **`claude-fm`**. Дальше:

```bash
claude-fm            # Claude Code на мозгах Cloud.ru
claude-fm -p 'привет'
```

Ключ хранится в `~/.dgx-claude/cloudru-fm.env` с правами `600` — в git и на экран не попадает.

## Какую модель

Проверено вживую — почти весь китайский каталог Cloud.ru доступен через Anthropic API:

| Модель | Годится | Заметка |
|---|---|---|
| **DeepSeek-V4-Pro** | ✅ по умолчанию | внутренняя (данные в РФ), сильная в агентных задачах |
| **Kimi-K2.6** / k2.5 / k2-thinking | ✅ | внутренняя |
| **Qwen3.5-397B-A17B** | ✅ | внутренняя, крупная |
| MiniMax-M3 / M2.5, GLM-5.2 / 4.7, MiMo, LongCat | ✅ | внутренние |
| DeepSeek-v3.2 / V3.1-Terminus | ✅ | внутренние |
| `anthropic/claude-haiku-4.5` (и др.) | ⚠️ | **настоящий Claude, но данные уходят из РФ и дороже** |
| **Qwen3.6-35B-A3B** | ❌ | по Anthropic-API даёт 403 «не подключена к проекту» — подключается в консоли Cloud.ru |

Сменить модель:
```bash
bash scripts/install-claude-fm.sh --model moonshotai/Kimi-K2.6
```

## Что стоит знать (честно)

- **По умолчанию — внутренняя модель** (DeepSeek-V4-Pro): данные остаются в инфраструктуре Cloud.ru
  (РФ). Внешние `anthropic/claude-*` — это настоящий Claude, но данные уходят наружу и это дороже;
  бери их только осознанно.
- **Вызов инструментов на не-Claude модели** может работать хуже, чем на настоящем Claude — агентный
  цикл Claude Code к этому требователен. Базовые ответы точно приходят (проверено), но полный
  tool-loop надо проверить смоук-тестом:
  ```bash
  claude-fm -p 'прочитай /etc/hostname и выполни uname -m'
  ```
  Если агент реально прочитал файл и выполнил команду — связка живая. Если только «рассказал» —
  на этой модели tool-use слабоват, попробуй другую (напр. настоящий `anthropic/claude-haiku-4.5`).
- **Ключ Cloud.ru — как пароль:** не в git, не в чат. Скрипт кладёт его в `.env` с `chmod 600`.

## Убрать

```bash
bash scripts/install-claude-fm.sh --remove
```

---

Почему это лучше туннеля и LiteLLM: Cloud.ru достаётся с DGX **напрямую** (не гео-блокируется),
поэтому не нужен ни нестабильный VPN-туннель, ни docker с LiteLLM. Один ключ, одна команда.
