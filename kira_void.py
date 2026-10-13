#!/usr/bin/env python3
"""Kira-Void: local Qwen assistant (Ollama). Stdlib only.

  python kira_void.py setup [preset|ollama-tag]   # build 'kira-void' (presets: default, smart,
                                                  # smarter, uncensored, uncensored-smart)
  python kira_void.py         # terminal chat
  python kira_void.py web     # web UI on http://127.0.0.1:8080
  python kira_void.py web --lan   # also serve the Android app over Wi-Fi
  python kira_void.py image "prompt"            # text -> image.png
  python kira_void.py edit in.png "prompt"      # edit an image by instruction
"""
import base64, json, os, subprocess, sys, urllib.request
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

OLLAMA = os.environ.get("OLLAMA_HOST", "http://127.0.0.1:11434")
MODEL = os.environ.get("KIRA_MODEL", "kira-void")
HERE = os.path.dirname(os.path.abspath(__file__))
STORE = os.path.expanduser("~/.kira-void/history.json")
TOKEN = os.environ.get("KIRA_TOKEN", "")  # optional password for the phone app / LAN access


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


def fetch_text(url, limit=20000):
    import re
    req = urllib.request.Request(url, headers={"User-Agent": "Mozilla/5.0 Kira-Void"})
    html = urllib.request.urlopen(req, timeout=30).read().decode("utf-8", "replace")
    html = re.sub(r"(?is)<(script|style).*?</\1>", " ", html)
    return re.sub(r"\s+", " ", re.sub(r"<[^>]+>", " ", html)).strip()[:limit]


def cli():
    global MODEL
    msgs = load()
    print(f"Kira-Void ({MODEL}). /reset, /model <name>, /system <prompt>, /web <url>, /file <path>, /img <prompt>, /exit.")
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
        if q.startswith("/system "):   # replace the persona / system prompt for this chat
            msgs = [m for m in msgs if m["role"] != "system"]
            msgs.insert(0, {"role": "system", "content": q[8:]}); save(msgs)
            print("system prompt set"); continue
        if q.startswith(("/web ", "/file ")):   # load a web page or local text file as context
            cmd, arg = q.split(maxsplit=1)
            try:
                text = fetch_text(arg) if cmd == "/web" else open(os.path.expanduser(arg), errors="replace").read()[:40000]
            except Exception as e:
                print(f"[error: {e}]"); continue
            msgs.append({"role": "user", "content": f"Reference material ({arg}):\n{text}"})
            msgs.append({"role": "assistant", "content": "Loaded. Ask me about it."}); save(msgs)
            print(f"loaded {len(text)} chars"); continue
        if q.startswith("/img "):
            import images
            try:
                open("image.png", "wb").write(images.generate(q[5:])); print("saved image.png")
            except Exception as e:
                print(f"[error: {e}]")
            continue
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

    def authorized(self):
        if TOKEN and self.headers.get("X-Kira-Token") != TOKEN:
            self.send_response(401); self.end_headers(); self.wfile.write(b"bad token")
            return False
        return True

    def do_GET(self):
        if self.path == "/ping":
            if not self.authorized():
                return
            body = json.dumps({"name": "Kira-Void", "model": MODEL}).encode()
            self.send_response(200); self.send_header("Content-Type", "application/json")
            self.end_headers(); self.wfile.write(body); return
        body = open(os.path.join(HERE, "web", "index.html"), "rb").read()
        self.send_response(200); self.send_header("Content-Type", "text/html; charset=utf-8")
        self.end_headers(); self.wfile.write(body)

    def do_POST(self):
        if not self.authorized():
            return
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


def web(lan=False):
    host = "0.0.0.0" if lan else "127.0.0.1"
    if lan:
        import socket
        s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        try:
            s.connect(("8.8.8.8", 80)); ip = s.getsockname()[0]
        except OSError:
            ip = "<this-pc-ip>"
        s.close()
        print(f"Kira-Void for phone: enter http://{ip}:8080 in the app settings")
        if not TOKEN:
            print("Tip: set KIRA_TOKEN=yourpassword so others on the network can't use it")
    print("Kira-Void web UI: http://127.0.0.1:8080")
    ThreadingHTTPServer((host, 8080), Handler).serve_forever()


def cli_image(argv):
    import argparse, images
    ap = argparse.ArgumentParser(prog="kira_void.py " + argv[0])
    if argv[0] == "edit":
        ap.add_argument("src")
    ap.add_argument("prompt")
    ap.add_argument("--neg", default="", help="extra negative prompt")
    ap.add_argument("--seed", type=int, help="fixed seed to reproduce a result")
    ap.add_argument("--steps", type=int, default=40)
    ap.add_argument("--size", default="1024x1024", help="WxH, e.g. 832x1216 for portrait")
    ap.add_argument("-n", type=int, default=1, help="number of variations")
    a = ap.parse_args(argv[1:])
    w, h = map(int, a.size.lower().split("x"))
    for i in range(a.n):
        seed = None if a.seed is None else a.seed + i
        if argv[0] == "image":
            png = images.generate(a.prompt, a.neg, a.steps, seed, w, h)
        else:
            png = images.edit(open(a.src, "rb").read(), a.prompt, a.steps)
        name = "image.png" if a.n == 1 else f"image-{i + 1}.png"
        open(name, "wb").write(png)
        print("saved", name)


if __name__ == "__main__":
    a = sys.argv[1:]
    if a[:1] in (["image"], ["edit"]):
        cli_image(a)
    else:
        if a[:1] == ["setup"]:
            setup(a[1] if len(a) > 1 else None)
        else:
            {"web": lambda: web("--lan" in a)}.get(a[0] if a else "", cli)()
