#!/usr/bin/env python3
"""Kira-Void: local Qwen assistant (Ollama). Stdlib only.

  python kira_void.py setup   # build the 'kira-void' model from ./Modelfile
  python kira_void.py         # terminal chat
  python kira_void.py web     # web UI on http://127.0.0.1:8080
"""
import json, os, subprocess, sys, urllib.request
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

OLLAMA = os.environ.get("OLLAMA_HOST", "http://127.0.0.1:11434")
MODEL = os.environ.get("KIRA_MODEL", "kira-void")
HERE = os.path.dirname(os.path.abspath(__file__))
STORE = os.path.expanduser("~/.kira-void/history.json")


def chat_stream(messages):
    req = urllib.request.Request(
        f"{OLLAMA}/api/chat",
        json.dumps({"model": MODEL, "messages": messages, "stream": True}).encode(),
        {"Content-Type": "application/json"},
    )
    with urllib.request.urlopen(req) as r:  # no timeout: long answers are fine
        for line in r:
            if line.strip():
                chunk = json.loads(line)
                yield chunk.get("message", {}).get("content", "")


def load():
    try:
        return json.load(open(STORE))
    except Exception:
        return []


def save(msgs):
    os.makedirs(os.path.dirname(STORE), exist_ok=True)
    json.dump(msgs, open(STORE, "w"), ensure_ascii=False)


def setup():
    subprocess.check_call(["ollama", "create", MODEL, "-f", os.path.join(HERE, "Modelfile")])


def cli():
    msgs = load()
    print(f"Kira-Void ({MODEL}). /reset clears memory, /exit quits.")
    while True:
        try:
            q = input("\n> ").strip()
        except (EOFError, KeyboardInterrupt):
            break
        if q in ("/exit", "/quit"):
            break
        if q == "/reset":
            msgs = []; save(msgs); print("memory cleared"); continue
        if not q:
            continue
        msgs.append({"role": "user", "content": q})
        out = ""
        for t in chat_stream(msgs):
            print(t, end="", flush=True); out += t
        print()
        msgs.append({"role": "assistant", "content": out})
        save(msgs)


class Handler(BaseHTTPRequestHandler):
    def log_message(self, *a): pass

    def do_GET(self):
        body = open(os.path.join(HERE, "web", "index.html"), "rb").read()
        self.send_response(200); self.send_header("Content-Type", "text/html; charset=utf-8")
        self.end_headers(); self.wfile.write(body)

    def do_POST(self):
        msgs = json.loads(self.rfile.read(int(self.headers["Content-Length"])))
        self.send_response(200); self.send_header("Content-Type", "text/plain; charset=utf-8")
        self.end_headers()
        try:
            for t in chat_stream(msgs):
                self.wfile.write(t.encode()); self.wfile.flush()
        except Exception as e:
            self.wfile.write(f"\n[error: {e}]".encode())


def web():
    print("Kira-Void web UI: http://127.0.0.1:8080")
    ThreadingHTTPServer(("127.0.0.1", 8080), Handler).serve_forever()


if __name__ == "__main__":
    {"setup": setup, "web": web}.get(sys.argv[1] if len(sys.argv) > 1 else "", cli)()
