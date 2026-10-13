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
python kira_void.py setup # creates the 'kira-void' model (see presets below)
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
- Extras: `--seed N` (reproduce a result), `--steps`, `--size 832x1216` (portrait), `--neg "..."`, `-n 4` (make 4 variations). `KIRA_LORA=path_or_repo,...` loads LoRA files for a specific style or more realism.
- Everything is also saved to `~/.kira-void/images`.

## Model presets
`python kira_void.py setup <preset>` (pulls the base on first use via `ollama pull <tag>` if missing):

| preset | base | notes |
|---|---|---|
| default | qwen3:8b | |
| smart / smarter | qwen3:14b / 32b | smarter, needs more VRAM |
| uncensored | huihui_ai/qwen3-abliterated:8b | community Qwen3 with refusals removed |
| uncensored-smart | huihui_ai/qwen3-abliterated:14b | |

Any other Ollama tag also works. In the terminal chat, `/model <name>` switches the active model on the fly (a second chat model). The tags above are community models and may be renamed; check ollama.com if a pull fails.

## Terminal chat commands
`/system <prompt>` set your own persona/system prompt, `/web <url>` read a web page into context, `/file <path>` read a local text file, `/img <prompt>` generate an image, `/model <name>` switch model, `/reset` clear memory.

## Android app (built on Codemagic)
The phone app (`android_app/`, Flutter) has two modes, switched in **Settings**:

- **On the phone (default):** Qwen runs fully offline on the phone (MediaPipe/LiteRT via `flutter_gemma`). On first launch pick a model and it downloads once from HuggingFace: Qwen 2.5 1.5B (1.6 GB, 6+ GB RAM), Qwen 3 0.6B (0.6 GB) or Qwen 2.5 0.5B (0.5 GB, weak phones). GPU is used when available, CPU otherwise. Downloaded models can be deleted in Settings.
- **On the PC:** chat goes to your PC's Kira-Void server (bigger models, better answers).

**Images on the phone** use Stable Diffusion 1.5 through Google's MediaPipe Image Generator (512×512, 20–90 s per picture, 6+ GB RAM). The model must be converted once:

1. On Codemagic run the **Kira-Void phone image model** workflow. It downloads SD 1.5 and produces `kira-void-image-model.zip` (~2 GB) as an artifact. To use a different SD 1.5-based model, change `SD15_MODEL_URL` (direct link to a `.safetensors`). SDXL/SD2/Flux models do not work on the phone.
2. Download the zip on the phone and in the app's **Images** tab tap **Choose file** (or paste a direct link to the zip).

Alternatively convert on a PC: `pip install torch safetensors numpy requests` then `python tools/convert_sd_for_phone.py model.safetensors kira-void-image-model.zip`.

With a photo selected, phone mode keeps the photo's outlines (edge plugin) and repaints it by the prompt; true prompt-based editing (InstructPix2Pix) and SDXL quality are PC-only.

PC server setup (optional: bigger chat models, SDXL images, real photo editing):

1. On the PC: `KIRA_TOKEN=yourpassword python kira_void.py web --lan` (on Windows: `set KIRA_TOKEN=yourpassword` first). It prints the address to use, e.g. `http://192.168.1.5:8080`.
2. Build the APK: on https://codemagic.io/apps add this repository, pick the **Kira-Void Android** workflow from `codemagic.yaml`, start the build and download `app-release.apk` from the build artifacts.
3. Install the APK on the phone (allow "install unknown apps"). For PC features open **Settings**, enter the address and password, tap **Save and check**.

Phone and PC must be on the same network. The APK is signed with a debug key, so it can be installed directly but not published to Google Play.
