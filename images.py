"""Local image generation / editing (diffusers). Adult content is not filtered.

Hard limits kept on purpose: nothing involving minors, and no sexual edits of
real people's photos without their consent (your responsibility, see README).
"""
import io, os, re

GEN_MODEL = os.environ.get("KIRA_IMAGE_MODEL", "stabilityai/stable-diffusion-xl-base-1.0")
EDIT_MODEL = os.environ.get("KIRA_EDIT_MODEL", "timbrooks/instruct-pix2pix")
OUT = os.path.expanduser("~/.kira-void/images")

_MINOR = re.compile(
    r"\b(child|children|kid|kids|minor|underage|under-age|loli|lolita|shota|toddler|"
    r"infant|preteen|pre-teen|teen(?:age|ager)?|schoolgirl|schoolboy|young[- ]?looking|"
    r"ребен\w*|детск\w*|дети|малолет\w*|несовершеннолет\w*|школьниц\w*|школьник\w*|подрост\w*|лоли)\b",
    re.I,
)
_pipes = {}


def check(prompt):
    if _MINOR.search(prompt):
        raise ValueError("Blocked: prompts involving minors are never allowed.")


def _device():
    import torch
    return ("cuda", torch.float16) if torch.cuda.is_available() else ("cpu", torch.float32)


def _pipe(kind):
    if kind in _pipes:
        return _pipes[kind]
    from diffusers import AutoPipelineForText2Image, StableDiffusionInstructPix2PixPipeline
    dev, dt = _device()
    if kind == "gen":
        p = AutoPipelineForText2Image.from_pretrained(GEN_MODEL, torch_dtype=dt)
    else:
        p = StableDiffusionInstructPix2PixPipeline.from_pretrained(
            EDIT_MODEL, torch_dtype=dt, safety_checker=None)
    if hasattr(p, "safety_checker"):
        p.safety_checker = None
    _pipes[kind] = p.to(dev)
    return _pipes[kind]


def _png(img):
    os.makedirs(OUT, exist_ok=True)
    path = os.path.join(OUT, f"{len(os.listdir(OUT)):05d}.png")
    img.save(path)
    b = io.BytesIO(); img.save(b, "PNG")
    return b.getvalue()


def generate(prompt, negative="", steps=30, seed=None):
    check(prompt)
    import torch
    g = torch.Generator().manual_seed(seed) if seed is not None else None
    img = _pipe("gen")(prompt=prompt, negative_prompt=negative or None,
                       num_inference_steps=steps, generator=g).images[0]
    return _png(img)


def edit(image_bytes, prompt, steps=30, image_guidance=1.5):
    check(prompt)
    from PIL import Image
    src = Image.open(io.BytesIO(image_bytes)).convert("RGB")
    img = _pipe("edit")(prompt, image=src, num_inference_steps=steps,
                        image_guidance_scale=image_guidance).images[0]
    return _png(img)
