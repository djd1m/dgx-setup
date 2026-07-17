#!/usr/bin/env python3
"""vless2xray — превратить vless:// ссылку в конфиг xray-КЛИЕНТА с локальным HTTP-inbound.

Вход:  одна vless:// ссылка (из твоей рабочей панели / клиента) — в argv[1] или из stdin.
Выход: JSON конфига xray на stdout. Локальный HTTP-прокси поднимается на 127.0.0.1:$HTTP_PORT.

Ссылка — это СЕКРЕТ (в ней UUID сервера). Скрипт ничего никуда не отправляет,
только печатает конфиг. Проверить корректность: xray run -test -c <файл>.
"""
import sys, json, os
from urllib.parse import urlparse, parse_qs, unquote

HTTP_PORT = int(os.environ.get("XRAY_HTTP_PORT", "10809"))
SOCKS_PORT = int(os.environ.get("XRAY_SOCKS_PORT", "10808"))


def build(link: str) -> dict:
    link = link.strip()
    if not link.startswith("vless://"):
        raise SystemExit("Ошибка: ссылка должна начинаться с vless:// — это не она.")

    u = urlparse(link)
    if not u.username:
        raise SystemExit("Ошибка: в ссылке нет UUID (часть до @).")
    uuid = u.username
    host = u.hostname
    port = u.port or 443
    q = {k: v[0] for k, v in parse_qs(u.query).items()}

    security = q.get("security", "none").lower()
    net = q.get("type", "tcp").lower()          # tcp | ws | grpc | xhttp | http | httpupgrade
    flow = q.get("flow", "")

    # --- stream settings ---
    stream = {"network": net, "security": security}

    if security == "tls":
        tls = {}
        if q.get("sni"):   tls["serverName"] = q["sni"]
        if q.get("fp"):    tls["fingerprint"] = q["fp"]
        if q.get("alpn"):  tls["alpn"] = unquote(q["alpn"]).split(",")
        if q.get("allowInsecure") in ("1", "true"):
            tls["allowInsecure"] = True
        stream["tlsSettings"] = tls
    elif security == "reality":
        r = {}
        if q.get("sni"):  r["serverName"] = q["sni"]
        if q.get("fp"):   r["fingerprint"] = q["fp"]
        if q.get("pbk"):  r["publicKey"] = q["pbk"]
        if q.get("sid"):  r["shortId"] = q["sid"]
        if q.get("spx"):  r["spiderX"] = unquote(q["spx"])
        stream["realitySettings"] = r

    path = unquote(q.get("path", "/"))
    hhost = q.get("host", "")

    if net == "ws":
        ws = {"path": path}
        if hhost: ws["headers"] = {"Host": hhost}
        stream["wsSettings"] = ws
    elif net in ("xhttp", "splithttp"):
        stream["network"] = "xhttp"
        xh = {"path": path}
        if hhost: xh["host"] = hhost
        if q.get("mode"): xh["mode"] = q["mode"]
        stream["xhttpSettings"] = xh
    elif net == "httpupgrade":
        hu = {"path": path}
        if hhost: hu["host"] = hhost
        stream["httpupgradeSettings"] = hu
    elif net == "grpc":
        g = {"serviceName": unquote(q.get("serviceName", ""))}
        if q.get("mode") == "multi": g["multiMode"] = True
        stream["grpcSettings"] = g
    elif net in ("http", "h2"):
        stream["network"] = "http"
        h2 = {"path": path}
        if hhost: h2["host"] = hhost.split(",")
        stream["httpSettings"] = h2
    # tcp: без доп. настроек (raw)

    user = {"id": uuid, "encryption": "none"}
    if flow:
        user["flow"] = flow

    outbound = {
        "tag": "proxy",
        "protocol": "vless",
        "settings": {"vnext": [{"address": host, "port": port, "users": [user]}]},
        "streamSettings": stream,
    }

    return {
        "log": {"loglevel": "warning"},
        "inbounds": [
            {
                "tag": "http-in",
                "listen": "127.0.0.1",
                "port": HTTP_PORT,
                "protocol": "http",
                "sniffing": {"enabled": True, "destOverride": ["http", "tls"]},
            },
            {
                "tag": "socks-in",
                "listen": "127.0.0.1",
                "port": SOCKS_PORT,
                "protocol": "socks",
                "settings": {"udp": True},
                "sniffing": {"enabled": True, "destOverride": ["http", "tls"]},
            },
        ],
        "outbounds": [
            outbound,
            {"tag": "direct", "protocol": "freedom"},
            {"tag": "block", "protocol": "blackhole"},
        ],
    }


if __name__ == "__main__":
    link = sys.argv[1] if len(sys.argv) > 1 else sys.stdin.read()
    print(json.dumps(build(link), indent=2, ensure_ascii=False))
