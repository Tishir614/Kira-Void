#!/usr/bin/env python3
"""Print the download URL of a Civitai model version, found by model id and version name.

  python tools/civitai_url.py 172268 "v2.1"      # OrbitMix v2.1
"""
import json, os, sys, urllib.request

model_id, version = sys.argv[1], sys.argv[2].lower().lstrip("v")
req = urllib.request.Request(f"https://civitai.com/api/v1/models/{model_id}", headers={"User-Agent": "Kira-Void"})
if os.environ.get("CIVITAI_TOKEN"):
    req.add_header("Authorization", f"Bearer {os.environ['CIVITAI_TOKEN']}")
data = json.load(urllib.request.urlopen(req, timeout=60))
for v in data["modelVersions"]:
    if v["name"].lower().lstrip("v").strip() == version or version in v["name"].lower():
        files = [f for f in v["files"] if f["name"].endswith(".safetensors")] or v["files"]
        print(f"{data['name']} {v['name']} (id {v['id']}, base {v.get('baseModel')}): {files[0]['name']}", file=sys.stderr)
        print(files[0]["downloadUrl"])
        break
else:
    sys.exit(f"version {sys.argv[2]!r} not found; available: {[v['name'] for v in data['modelVersions']]}")
