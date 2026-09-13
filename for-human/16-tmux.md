# 16. tmux на DGX: сессии агентов, которые возвращаются после перезагрузки

Сценарий: на DGX запускаешь Claude Code, Codex или TUI агента в терминале по SSH и
хочешь, чтобы (а) обрыв связи не убивал работу и (б) после перезагрузки машины
сессия снова была на месте. Первое tmux даёт сам по себе. Второе — **не даёт и дать
не может**, и большинство «инструкций из интернета» об этом умалчивают.

> Всё ниже проверено на Ubuntu 24.04 (DGX OS 7 — это кастомизированная Ubuntu 24.04
> под arm64, см. [00-ollama.md](00-ollama.md)); tmux в штатном архиве — версия 3.4,
> пакет собран и под arm64. Где не проверено — так и написано, **NOT VERIFIED**.

## Главное, что надо понять

**Сессия tmux не переживает перезагрузку.** Все сессии живут внутри одного процесса
`tmux: server`; при `reboot` он умирает вместе с тем, что внутри, — сборкой, `ollama pull`,
Claude Code. Ничего из этого «сохранить» нельзя. Плагины вроде `tmux-resurrect`
восстанавливают раскладку окон, а не состояние программ.

| Событие | Сессия выживает? | Чем обеспечивается |
|---|---|---|
| Обрыв SSH, закрытый ноутбук | Да | поведение tmux по умолчанию |
| `exit` из последнего SSH-логина | Да, если `KillUserProcesses=no` | значение по умолчанию в Ubuntu; `enable-linger` даёт гарантию |
| **Перезагрузка DGX** | **Нет** | ничем; сессию можно только пересоздать при загрузке |

Поэтому честная цель: после загрузки сессия `main` **существует**, `tmux attach -t main`
работает сразу, а внутри — чистая оболочка. Что было до перезагрузки, не вернётся.

## Как это стыкуется с агентами из [11](11-multi-agent-host.md)

Фоновые агенты (Hermes, OpenClaw, Ouroboros) на DGX живут как `--user`-юниты systemd,
и в [11](11-multi-agent-host.md) для их автозапуска уже рекомендован
`loginctl enable-linger <user>`. tmux — про **интерактивную** работу: Claude Code,
`codex`, `hermes chat`. Это разные вещи, и смешивать их не надо:

- демон агента → systemd-юнит, он и есть «переживание перезагрузки»;
- терминальная сессия человека → tmux; после ребута её пересоздаёт юнит из этого
  документа, но **запускать в ней агента автоматически не стоит**: Claude Code при
  старте задаёт вопросы (доверие каталогу, подтверждения), и без человека сессия
  просто повиснет на диалоге.

Тот же `enable-linger`, что нужен для юнитов агентов, нужен и для tmux-юнита — то есть
если ты прошёл [11](11-multi-agent-host.md), половина работы уже сделана.

## Установка (одна команда)

```bash
sudo apt-get update -qq && sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -qq tmux
tmux -V
```

Ожидаемо `tmux 3.4`. Ставится **из штатного архива**, не из PPA и не из исходников:
DGX OS получает обновления безопасности через apt, и пакет извне в эту цепочку не
попадёт. Версии 3.2+ достаточно для всего ниже.

## Сессия, которая возвращается после перезагрузки

Механизм: пользовательский systemd-юнит создаёт сессию при загрузке, а linger разрешает
пользовательскому менеджеру стартовать без интерактивного входа. Без linger юнит
запустится только при первом SSH-логине — то есть ровно тогда, когда он уже не нужен.

```bash
sudo loginctl enable-linger "$USER"
mkdir -p ~/.config/systemd/user
cat > ~/.config/systemd/user/tmux-main.service <<'UNIT'
[Unit]
Description=tmux session "main"
After=default.target

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/usr/bin/tmux new-session -A -d -s main
ExecStop=/usr/bin/tmux kill-session -t main

[Install]
WantedBy=default.target
UNIT
systemctl --user daemon-reload
systemctl --user enable --now tmux-main.service
tmux ls
```

Почему юнит именно такой:

- `new-session -A -d -s main` — `-A` значит «подключиться, если есть, иначе создать».
  Повторный запуск при живой сессии не падает с `duplicate session`.
- `Type=oneshot` + `RemainAfterExit=yes` — команда завершается сразу (сервер tmux
  демонизируется сам), а юнит остаётся `active`, и systemd не убирает cgroup с живым
  сервером. `Type=forking` хуже: если сервер уже поднят другой сессией, `new-session` не
  форкает нового демона и systemd теряет главный процесс.
- `KillMode=none` из старых рецептов не используется: в systemd 255 (Ubuntu 24.04) он
  объявлен устаревшим и пишет предупреждение в журнал.

## Проверка настоящей перезагрузкой

Единственная проверка, которая что-то доказывает. Она перезагружает DGX — убедись, что
никто не гонит на нём длинную задачу, и что фоновые агенты из [11](11-multi-agent-host.md)
тоже поднимутся сами (у них свои юниты).

```bash
tmux send-keys -t main 'date -u > /tmp/tmux-reboot-probe' C-m
sudo reboot
```

После загрузки:

```bash
uptime -p; systemctl --user is-active tmux-main.service; tmux ls; tmux attach -t main
```

Ожидаемо: аптайм — минуты; `active`; сессия `main` есть; внутри — чистая оболочка, а
файл `/tmp/tmux-reboot-probe` существует. Это и есть доказательство, что окно новое, а
не «сохранённое».

Если `tmux ls` говорит `no server running` — почти всегда не включён linger
(`loginctl show-user "$USER" -p Linger` должно быть `yes`) или юнит не enabled.

## Что стоит знать честно

- **Мышь в tmux и TUI агентов.** `set -g mouse on` удобно для панелей, но перехватывает
  выделение и отдаёт TUI события прокрутки. Для Claude Code/Codex в tmux лучше без мыши.
  Три строки, которые для TUI действительно важны: `set -sg escape-time 10`,
  `set -g history-limit 100000`, `set -g default-terminal "tmux-256color"`.
- **Автоподключение при SSH-входе** через `.bashrc` — удобно, но любая ошибка в
  `~/.tmux.conf` после этого ломает каждый вход. Безопаснее алиас:
  `alias m='tmux new-session -A -s main'`.
- **`tmux-resurrect` / `tmux-continuum`** здесь не предлагаются: тянут менеджер плагинов,
  который клонирует код с GitHub в домашний каталог, а восстанавливают только раскладку.
  На машине, где агенты выполняют произвольные команды, лишняя доверенная поверхность
  не нужна.
- **NOT VERIFIED:** поведение `KillUserProcesses` и linger на DGX OS 7 проверялось на
  обычной Ubuntu 24.04, не на самом DGX; NVIDIA в этой части systemd не патчит, но
  проверка ребутом выше нужна именно поэтому.

## Откат

```bash
systemctl --user disable --now tmux-main.service
rm -f ~/.config/systemd/user/tmux-main.service
systemctl --user daemon-reload
sudo loginctl disable-linger "$USER"     # только если linger не нужен юнитам агентов из 11
```
