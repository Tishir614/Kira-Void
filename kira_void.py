#!/usr/bin/env python3
"""Kira-Void: local Qwen assistant (Ollama). Stdlib only.

  python kira_void.py setup [preset|ollama-tag]   # build 'kira-void' (presets: default, smart,
                                                  # smarter, uncensored, uncensored-smart)
  python kira_void.py         # terminal chat
  python kira_void.py web     # web UI on http://127.0.0.1:8080
  python kira_void.py image "prompt"            # text -> image.png
  python kira_void.py edit in.png "prompt"      # edit an image by instruction
"""
import base64, json, os, subprocess, sys, urllib.request
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


PRESETS = {
    "default": "qwen3:8b",
    "smart": "qwen3:14b",          # needs ~10 GB VRAM
    "smarter": "qwen3:32b",        # needs ~20 GB VRAM
    "uncensored": "huihui_ai/qwen3-abliterated:8b",   # Qwen3 with refusals removed
    "uncensored-smart": "huihui_ai/qwen3-abliterated:14b",
}


def setup(preset=None):
    """Build the 'kira-void' model; preset or any ollama tag replaces FROM in the Modelfile."""
    base = PRESETS.get(preset, preset)
    text = open(os.path.join(HERE, "Modelfile")).read()
    if base:
        text = "\n".join(f"FROM {base}" if l.startswith("FROM ") else l for l in text.split("\n"))
    path = os.path.join(HERE, ".Modelfile.build")
    open(path, "w").write(text)
    try:
        subprocess.check_call(["ollama", "create", MODEL, "-f", path])
    finally:
        os.remove(path)


def cli():
    global MODEL
    msgs = load()
    print(f"Kira-Void ({MODEL}). /reset clears memory, /model <name> switches model, /exit quits.")
    while True:
        try:
            q = input("\n> ").strip()
        except (EOFError, KeyboardInterrupt):
            break
        if q in ("/exit", "/quit"):
            break
        if q.startswith("/model"):
            MODEL = q.split(maxsplit=1)[1] if " " in q else MODEL
            print(f"model: {MODEL}"); continue
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
        data = json.loads(self.rfile.read(int(self.headers["Content-Length"])))
        if self.path in ("/image", "/edit"):
            return self.image(data)
        msgs = data
        self.send_response(200); self.send_header("Content-Type", "text/plain; charset=utf-8")
        self.end_headers()
        try:
            for t in chat_stream(msgs):
                self.wfile.write(t.encode()); self.wfile.flush()
        except Exception as e:
            self.wfile.write(f"\n[error: {e}]".encode())


    def image(self, d):
        import images
        try:
            if self.path == "/image":
                png = images.generate(d["prompt"], d.get("negative", ""))
            else:
                png = images.edit(base64.b64decode(d["image"]), d["prompt"])
            code, ctype, body = 200, "image/png", png
        except Exception as e:
            code, ctype, body = 400, "text/plain; charset=utf-8", str(e).encode()
        self.send_response(code); self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(body))); self.end_headers()
        self.wfile.write(body)


def web():
    print("Kira-Void web UI: http://127.0.0.1:8080")
    ThreadingHTTPServer(("127.0.0.1", 8080), Handler).serve_forever()


def cli_image(argv):
    import images
    if argv[0] == "image":
        png = images.generate(argv[1])
    else:
        png = images.edit(open(argv[1], "rb").read(), argv[2])
    open("image.png", "wb").write(png)
    print("saved image.png")


if __name__ == "__main__":
    a = sys.argv[1:]
    if a[:1] in (["image"], ["edit"]):
        cli_image(a)
    else:
        if a[:1] == ["setup"]:
            setup(a[1] if len(a) > 1 else None)
        else:
            {"web": web}.get(a[0] if a else "", cli)()
