# 16. tmux на DGX: сессия, которая возвращается после перезагрузки — рецепт

**Цель:** поставить tmux из штатного архива и сделать так, чтобы после перезагрузки DGX
сессия `main` существовала и `tmux attach -t main` работал сразу. Объяснения и
ограничения — в [for-human/16-tmux.md](../for-human/16-tmux.md).

## 🛑 Прежде чем делать — что НЕ обещать человеку

- Сессия tmux **не переживает перезагрузку**: сервер `tmux` умирает вместе с системой.
  Этот рецепт **пересоздаёт пустую** сессию при загрузке, а не сохраняет работавшие
  программы. Не формулировать результат как «сессии сохраняются».
- В пересозданной сессии **не запускать агента автоматически** (Claude Code, Codex,
  Hermes-TUI): они задают вопросы при старте и без человека повиснут на диалоге.
  Фоновые агенты — это `--user`-юниты из [11-multi-agent-host.md](11-multi-agent-host.md).

## Предусловия

| Проверка | Ожидаемо | Если не так |
|---|---|---|
| `. /etc/os-release; echo $VERSION_ID` | `24.04` (DGX OS 7) или `22.04` | другая ОС → **STOP**, рецепт проверен только на Ubuntu |
| `systemctl --user show-environment >/dev/null && echo ok` | `ok` | нет `systemd --user` (контейнер) → **STOP**, автозапуск невозможен |
| `grep -rn '^\s*KillUserProcesses' /etc/systemd/logind.conf /etc/systemd/logind.conf.d/ 2>/dev/null` | пусто (по умолчанию `no`) | `yes` → шаг 2 становится обязательным, не опциональным |
| `command -v tmux && tmux -V` | отсутствует или `tmux 3.2+` | — |

## Шаги

### Шаг 1. Установка из штатного архива

```bash
sudo apt-get update -qq && sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -qq tmux
tmux -V
apt-cache policy tmux | sed -n '1,4p'
```

Ожидаемо: `tmux 3.4` на 24.04 (`3.2a` на 22.04); источник — `archive.ubuntu.com` или
`ports.ubuntu.com` (arm64), **не** PPA. PPA и сборку из исходников не предлагать.

### Шаг 2. Linger

```bash
sudo loginctl enable-linger "$USER"
loginctl show-user "$USER" -p Linger
```

Ожидаемо: `Linger=yes`. Если пользователь уже проходил [11](11-multi-agent-host.md),
linger может быть включён — команда идемпотентна.

### Шаг 3. Юнит

```bash
mkdir -p ~/.config/systemd/user
cat > ~/.config/systemd/user/tmux-main.service <<'UNIT'
[Unit]
Description=tmux session "main"
Documentation=man:tmux(1)
After=default.target

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/usr/bin/tmux new-session -A -d -s main
ExecStop=/usr/bin/tmux kill-session -t main
ExecReload=/usr/bin/tmux source-file %h/.tmux.conf

[Install]
WantedBy=default.target
UNIT
systemctl --user daemon-reload
systemctl --user enable --now tmux-main.service
systemctl --user is-active tmux-main.service
tmux ls
```

Ожидаемо: `active`; строка `main: 1 windows (created …)`.

Не менять: `-A` (идемпотентность при живой сессии), `Type=oneshot` + `RemainAfterExit=yes`
(при уже поднятом сервере `Type=forking` теряет главный процесс), отсутствие
`KillMode=none` (устарел в systemd 255, пишет предупреждение).

### Шаг 4. Идемпотентность

```bash
systemctl --user restart tmux-main.service; systemctl --user is-active tmux-main.service; tmux ls
```

Ожидаемо: `active`, сессия `main` на месте, ошибок `duplicate session` нет.

### Шаг 5. Проверка перезагрузкой (только по явному запросу человека)

Перезагружает машину. Спросить человека, убедиться, что на DGX нет длинной задачи.

```bash
tmux send-keys -t main 'date -u > /tmp/tmux-reboot-probe' C-m
sudo reboot
```

После загрузки, в новой SSH-сессии:

```bash
uptime -p; systemctl --user is-active tmux-main.service; tmux ls; ls -l /tmp/tmux-reboot-probe
```

Ожидаемо: аптайм в минутах; `active`; сессия `main` есть; файл-маркер существует
(доказательство, что до ребута в сессии что-то работало, а после — окно новое).

## Стоп-условия

| Симптом | Причина | Действие |
|---|---|---|
| после ребута `tmux ls` → `no server running` | linger выключен или юнит не enabled | `loginctl show-user "$USER" -p Linger`; `systemctl --user is-enabled tmux-main.service` |
| `systemctl --user` → `Failed to connect to bus` | нет `XDG_RUNTIME_DIR` (вход через `su`, а не SSH) | войти по SSH под этим пользователем; не чинить экспортом переменных вслепую |
| `apt-cache policy tmux` показывает сторонний источник | на машине уже подключён PPA | **STOP**, сообщить человеку; не переустанавливать |

## Критерий готовности

- `tmux -V` → 3.2+ из штатного архива.
- `Linger=yes`; `tmux-main.service` → `enabled`, `active`.
- Шаг 4 проходит без ошибок.
- Шаг 5 выполнен (или человек явно отложил ребут — тогда так и написать в отчёте:
  «проверка перезагрузкой не выполнялась»).
- В отчёте человеку нет формулировки «сессии сохраняются после перезагрузки».
