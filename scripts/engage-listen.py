#!/usr/bin/env python3
"""Exclusive TCP listener that relays a reverse shell into this terminal."""
import os
import select
import socket
import sys

def main() -> int:
    if len(sys.argv) != 2:
        print("usage: engage-listen.py PORT", file=sys.stderr)
        return 2
    port = int(sys.argv[1])
    sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    try:
        sock.bind(("0.0.0.0", port))
    except OSError as exc:
        if exc.errno == 98:
            print(
                f"[listener] FEHLER: Port {port} ist belegt (alter Listener). "
                "Engage räumt den Port beim nächsten Lauf.",
                flush=True,
            )
            return 1
        raise
    sock.listen(1)
    print(f"[listener] warte auf 0.0.0.0:{port}", flush=True)
    conn, addr = sock.accept()
    print(f"[listener] Shell von {addr[0]}:{addr[1]} — Befehle tippen (whoami, id)", flush=True)
    conn.setblocking(False)
    try:
        os.set_blocking(0, False)
    except OSError:
        pass
    while True:
        readable, _, _ = select.select([conn, sys.stdin], [], [], 1.0)
        if conn in readable:
            data = conn.recv(4096)
            if not data:
                print("\n[listener] Verbindung zu", flush=True)
                return 0
            os.write(1, data)
        if sys.stdin in readable:
            data = os.read(0, 4096)
            if not data:
                return 0
            conn.sendall(data)

if __name__ == "__main__":
    raise SystemExit(main())
