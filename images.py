"""Local image generation / editing (diffusers). Adult content is not filtered.

Hard limits kept on purpose: nothing involving minors, and no sexual edits of
real people's photos without their consent (your responsibility, see README).
"""
import io, os, re, time, uuid

GEN_MODEL = os.environ.get("KIRA_IMAGE_MODEL", "stabilityai/stable-diffusion-xl-base-1.0")
REFINER_MODEL = os.environ.get("KIRA_REFINER", "stabilityai/stable-diffusion-xl-refiner-1.0")  # "none" disables
LORAS = [x for x in os.environ.get("KIRA_LORA", "").split(",") if x]  # LoRA files / HF repos for style & realism
LOWVRAM = os.environ.get("KIRA_LOWVRAM") == "1"
EDIT_MODEL = os.environ.get("KIRA_EDIT_MODEL", "timbrooks/instruct-pix2pix")
OUT = os.path.expanduser("~/.kira-void/images")

_MINOR = re.compile(
    r"\b(child|children|kid|kids|minor|underage|under-age|loli|lolita|shota|toddler|"
    r"infant|preteen|pre-teen|teen(?:age|ager)?|schoolgirl|schoolboy|young[- ]?looking|"
    r"ребен\w*|детск\w*|дети|малолет\w*|несовершеннолет\w*|школьниц\w*|школьник\w*|подрост\w*|лоли)\b",
    re.I,
)
# Numeric ages: "12-year-old", "12 yo", "12 y/o", "aged 12", "age: 12", "12 лет", "12-летняя"
_AGE = re.compile(
    r"(?:\b(\d{1,2})\s*[- ]?\s*(?:years?[- ]?old|yrs?[- ]?old|y/?o\b|yo\b|лет|летн\w*|года\b|год\b)"
    r"|\b(?:aged?|возраст\w*)\s*[:=]?\s*(\d{1,2})\b)", re.I)
_pipes = {}

QUALITY = ("masterpiece, best quality, ultra detailed, sharp focus, realistic skin texture, "
           "natural lighting, professional photo, 8k, anatomically correct, perfect hands, five fingers")
NEGATIVE = ("extra limbs, extra arms, extra legs, three arms, three legs, extra fingers, missing fingers, "
            "fused fingers, mutated hands, malformed limbs, deformed, bad anatomy, bad proportions, "
            "disfigured, long neck, cloned face, duplicate, asymmetrical eyes, blurry, lowres, jpeg artifacts, "
            "watermark, text, signature, cropped, worst quality, low quality, cartoon, 3d render")


def check(prompt):
    ages = [int(n) for m in _AGE.finditer(prompt) for n in m.groups() if n]
    if _MINOR.search(prompt) or any(a < 18 for a in ages):
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
        for i, lora in enumerate(LORAS):
            p.load_lora_weights(lora, adapter_name=f"lora{i}")
        if LORAS:
            p.set_adapters([f"lora{i}" for i in range(len(LORAS))])
        _setup(p, dev)
        _pipes[kind] = p
        return p
    elif kind == "refiner":
        from diffusers import StableDiffusionXLImg2ImgPipeline
        base = _pipe("gen")
        p = StableDiffusionXLImg2ImgPipeline.from_pretrained(
            REFINER_MODEL, text_encoder_2=base.text_encoder_2, vae=base.vae, torch_dtype=dt)
        _setup(p, dev)
        _pipes[kind] = p
        return p
    else:
        p = StableDiffusionInstructPix2PixPipeline.from_pretrained(
            EDIT_MODEL, torch_dtype=dt, safety_checker=None)
    p.safety_checker = None
    _pipes[kind] = p.to(dev)
    return _pipes[kind]


def _setup(p, dev):
    from diffusers import DPMSolverMultistepScheduler
    p.scheduler = DPMSolverMultistepScheduler.from_config(
        p.scheduler.config, use_karras_sigmas=True, algorithm_type="sde-dpmsolver++")
    if hasattr(p, "safety_checker"):
        p.safety_checker = None
    if dev == "cuda" and LOWVRAM:
        p.enable_model_cpu_offload()
    else:
        p.to(dev)
    if hasattr(p, "enable_vae_tiling"):
        p.enable_vae_tiling()


def _png(img):
    os.makedirs(OUT, exist_ok=True)
    path = os.path.join(OUT, f"{time.strftime('%Y%m%d-%H%M%S')}-{uuid.uuid4().hex[:6]}.png")
    img.save(path)
    b = io.BytesIO(); img.save(b, "PNG")
    return b.getvalue()


def generate(prompt, negative="", steps=40, seed=None, width=1024, height=1024, guidance=6.5):
    """Base SDXL does the first 80% of denoising, the refiner (2nd model) finishes the last 20%."""
    check(prompt)
    import torch
    g = torch.Generator().manual_seed(seed) if seed is not None else None
    kw = dict(prompt=f"{prompt}, {QUALITY}", negative_prompt=f"{negative}, {NEGATIVE}".strip(", "),
              num_inference_steps=steps, guidance_scale=guidance, generator=g)
    kw.update(width=width, height=height)
    use_ref = REFINER_MODEL.lower() != "none"
    if use_ref:
        latents = _pipe("gen")(**kw, denoising_end=0.8, output_type="latent").images
        img = _pipe("refiner")(prompt=kw["prompt"], negative_prompt=kw["negative_prompt"],
                               num_inference_steps=steps, guidance_scale=guidance, generator=g,
                               denoising_start=0.8, image=latents).images[0]
    else:
        img = _pipe("gen")(**kw).images[0]
    return _png(img)


def edit(image_bytes, prompt, steps=30, image_guidance=1.5):
    check(prompt)
    from PIL import Image
    src = Image.open(io.BytesIO(image_bytes)).convert("RGB")
    src.thumbnail((768, 768))
    img = _pipe("edit")(prompt, image=src, negative_prompt=NEGATIVE, num_inference_steps=steps,
                        image_guidance_scale=image_guidance, guidance_scale=7.5).images[0]
    return _png(img)
