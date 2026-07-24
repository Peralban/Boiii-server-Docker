#!/usr/bin/env python3
"""
RCON terminal for the BO3 server (classic Call of Duty UDP RCON protocol).

Usage:
    rcon                 -> interactive terminal
    rcon status          -> run a single command and print the reply

The password is resolved in this order:
  1. the RCON_PASSWORD environment variable
  2. the `set rcon_password "..."` line of the rendered server config
"""
import os
import re
import socket
import sys

HOST = os.environ.get("RCON_HOST", "127.0.0.1")
PORT = int(os.environ.get("GAME_PORT", "27017"))
TIMEOUT = float(os.environ.get("RCON_TIMEOUT", "1.5"))

PREFIX = b"\xff\xff\xff\xff"


def read_password():
    """Resolve the RCON password from the environment or the rendered config."""
    env = os.environ.get("RCON_PASSWORD")
    if env:
        return env

    # Fall back to the rendered config (the one in /config is a template and
    # still holds the ${RCON_PASSWORD} placeholder).
    server_dir = os.environ.get("SERVER_DIR", "/data/serverfiles")
    cfg_name = os.environ.get("SERVER_CFG", "server.cfg")
    path = os.path.join(server_dir, "UnrankedServer", "zone", cfg_name)
    try:
        with open(path, "r", encoding="utf-8", errors="replace") as fh:
            match = re.search(
                r'^\s*set\s+rcon_password\s+"([^"]*)"', fh.read(), re.MULTILINE
            )
            if match:
                return match.group(1)
    except OSError:
        pass
    return ""


def send_command(sock, password, command):
    """Send one RCON command and collect the reply packets."""
    payload = PREFIX + b"rcon " + password.encode() + b" " + command.encode()
    sock.sendto(payload, (HOST, PORT))

    parts = []
    while True:
        try:
            data, _ = sock.recvfrom(65535)
        except socket.timeout:
            break
        if data.startswith(PREFIX):
            data = data[len(PREFIX):]
        if data.startswith(b"print\n"):
            data = data[len(b"print\n"):]
        parts.append(data.decode("utf-8", "replace"))
    return "".join(parts).strip()


def main():
    password = read_password()
    if not password:
        print("ERROR: no RCON password found.", file=sys.stderr)
        print("Set RCON_PASSWORD in your .env file.", file=sys.stderr)
        return 1

    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    sock.settimeout(TIMEOUT)

    # Single command mode
    if len(sys.argv) > 1:
        reply = send_command(sock, password, " ".join(sys.argv[1:]))
        print(reply if reply else "(no reply from server)")
        return 0

    # Interactive terminal mode
    print(f"RCON terminal -> {HOST}:{PORT}")
    print("Examples: status | serverinfo | map_rotate | say hello | kick <player>")
    print("Type 'exit' or press Ctrl-D to quit.\n")

    while True:
        try:
            line = input("rcon> ").strip()
        except (EOFError, KeyboardInterrupt):
            print()
            return 0
        if not line:
            continue
        if line == "exit":
            return 0
        reply = send_command(sock, password, line)
        print(reply if reply else "(no reply from server)")


if __name__ == "__main__":
    sys.exit(main())
