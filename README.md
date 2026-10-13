# Kira-Void

Local, free chat app on top of **Qwen** (via [Ollama](https://ollama.com)). Runs fully offline: no API key, no quotas, no cloud.

## What "smarter / unlimited" means here
- Qwen3 (reasoning model) with a tuned system prompt and sampling (`Modelfile`).
- 32k context window and no output-length cap (`num_predict -1`), no request timeouts.
- Persistent memory in the terminal chat (`~/.kira-void/history.json`).
- The prompt removes disclaimers and allows adult/NSFW conversation. The base model's own alignment is not retrained; if it still hedges, try a community abliterated Qwen in `Modelfile` `FROM`.

## Run
```
ollama pull qwen3:8b      # use qwen3:14b / 32b if you have the VRAM (edit Modelfile FROM)
python kira_void.py setup # creates the 'kira-void' model
python kira_void.py       # terminal chat
python kira_void.py web   # browser UI at http://127.0.0.1:8080
```
Requires Python 3.8+ and Ollama; no pip packages.

## Images (text-to-image and edit-by-prompt)
```
pip install torch diffusers transformers accelerate safetensors pillow
python kira_void.py image "your prompt"          # -> image.png
python kira_void.py edit photo.png "make it night, add rain"
```
In the web UI type `/img your prompt`, or attach a picture and type the change you want.
- Generation uses SDXL (`KIRA_IMAGE_MODEL`, e.g. set any NSFW-capable SDXL checkpoint from Hugging Face); editing uses InstructPix2Pix (`KIRA_EDIT_MODEL`). The NSFW safety checker is disabled; adult content is not filtered. A GPU is strongly recommended.
- Kept deliberately: prompts mentioning minors are blocked. Do not use edit mode to make sexual images of real people without their consent.
- Quality: 1024px SDXL, DPM++ SDE Karras, 40 steps, automatic quality prompt plus a strong negative prompt against extra limbs/fingers and bad anatomy. This reduces such errors a lot but cannot eliminate them; just regenerate or change the seed.
- Second model: the SDXL **refiner** (`KIRA_REFINER`, `none` to disable) finishes the last 20% of denoising for sharper skin and detail. Needs ~16 GB VRAM; set `KIRA_LOWVRAM=1` to offload to CPU on smaller GPUs.
- Best photo realism: point `KIRA_IMAGE_MODEL` at a photoreal SDXL checkpoint (e.g. RealVisXL, Juggernaut XL).
- Everything is also saved to `~/.kira-void/images`.
