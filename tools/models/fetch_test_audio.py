#!/usr/bin/env python3
"""Fetch a real, openly licensed (CC0 / CC BY) research-grade bird recording from iNaturalist
for model validation, and record its attribution. Writes <work>/test_source.(ext) and
<work>/test_source.json. Conversion to 48 kHz mono WAV is done by the workflow (afconvert)."""
import json
import os
import sys
import urllib.parse
import urllib.request

work = sys.argv[1] if len(sys.argv) > 1 else "work"
taxon = sys.argv[2] if len(sys.argv) > 2 else "Turdus merula"
os.makedirs(work, exist_ok=True)
url = ("https://api.inaturalist.org/v1/observations?sounds=true&quality_grade=research"
       "&sound_license=cc0,cc-by&per_page=10&order_by=votes&taxon_name=" + urllib.parse.quote(taxon))
req = urllib.request.Request(url, headers={"User-Agent": "WildID-model-validation/1.0"})
data = json.load(urllib.request.urlopen(req))
for obs in data["results"]:
    for s in obs.get("sounds", []):
        f = s.get("file_url")
        if not f:
            continue
        ext = os.path.splitext(f.split("?")[0])[1] or ".mp3"
        dest = os.path.join(work, "test_source" + ext)
        urllib.request.urlretrieve(f, dest)
        meta = {"taxon": obs["taxon"]["name"], "observation": obs["uri"], "file": f,
                "license": s.get("license_code"), "attribution": s.get("attribution"), "path": dest}
        json.dump(meta, open(os.path.join(work, "test_source.json"), "w"), indent=1)
        print(json.dumps(meta, indent=1))
        sys.exit(0)
sys.exit("no sound found")
