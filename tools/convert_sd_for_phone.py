#!/usr/bin/env python3
"""Convert a Stable Diffusion 1.5 checkpoint into the MediaPipe Image Generator
format used by the Kira-Void Android app, and pack it into one zip.

  pip install torch safetensors numpy requests
  python tools/convert_sd_for_phone.py model.safetensors kira-void-image-model.zip

Works with .safetensors and .ckpt files of any SD 1.5-based model
(SDXL / SD2 / Flux are NOT supported by the phone engine).
Based on Google's mediapipe-samples tools/image_generator_converter/convert.py.
"""
import os, sys, tempfile, zipfile

import requests

VOCAB_URL = "https://openaipublic.blob.core.windows.net/clip/bpe_simple_vocab_16e6.txt"


def load_state(path):
    if path.endswith(".safetensors"):
        from safetensors.torch import load_file
        return load_file(path, device="cpu")
    import torch
    ckpt = torch.load(path, map_location="cpu", weights_only=False)
    return ckpt.get("state_dict", ckpt)


def main(src, dst):
    state = load_state(src)
    if not any(k.startswith("model.diffusion_model.") for k in state):
        sys.exit("Not an SD 1.5 single-file checkpoint (no model.diffusion_model.* weights).")
    with tempfile.TemporaryDirectory() as tmp, zipfile.ZipFile(dst, "w", zipfile.ZIP_STORED, allowZip64=True) as z:
        vocab = os.path.join(tmp, "bpe_simple_vocab_16e6.txt")
        with requests.get(VOCAB_URL, timeout=60) as r:
            r.raise_for_status()
            open(vocab, "wb").write(r.content)
        z.write(vocab, "bins/bpe_simple_vocab_16e6.txt")
        n = 0
        for k, v in state.items():
            if "first_stage_model.encoder" in k or "model_ema." in k or not hasattr(v, "numpy"):
                continue
            f = os.path.join(tmp, "w.bin")
            v.float().numpy().astype("float16").tofile(f)
            z.write(f, f"bins/{k}.bin")
            n += 1
    print(f"{dst}: {n} tensors, {os.path.getsize(dst) / 2**30:.2f} GB")


if __name__ == "__main__":
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    main(sys.argv[1], sys.argv[2])
