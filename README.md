# Kira-Void

Local, free chat app on top of **Qwen** (via [Ollama](https://ollama.com)). Runs fully offline: no API key, no quotas, no cloud.

## What "smarter / unlimited" means here
- Qwen3 (reasoning model) with a tuned system prompt and sampling (`Modelfile`).
- 32k context window and no output-length cap (`num_predict -1`), no request timeouts.
- Persistent memory in the terminal chat (`~/.kira-void/history.json`).
- Safety alignment of the base model is **not** stripped out; the prompt only removes needless disclaimers.

## Run
```
ollama pull qwen3:8b      # use qwen3:14b / 32b if you have the VRAM (edit Modelfile FROM)
python kira_void.py setup # creates the 'kira-void' model
python kira_void.py       # terminal chat
python kira_void.py web   # browser UI at http://127.0.0.1:8080
```
Requires Python 3.8+ and Ollama; no pip packages.
