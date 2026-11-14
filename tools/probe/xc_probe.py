"""Research probe: documents the xeno-canto v3 API and iNaturalist response shapes.
The API key is read from the environment and never printed."""
import html
import json
import os
import re
import urllib.parse
import urllib.request


def get(url, binary=False):
    req = urllib.request.Request(url, headers={"User-Agent": "WildID-probe/1.0"})
    with urllib.request.urlopen(req, timeout=60) as r:
        data = r.read()
        return data if binary else data.decode("utf-8", "replace")


try:
    page = get("https://xeno-canto.org/explore/api")
    text = re.sub(r"<script.*?</script>|<style.*?</style>", "", page, flags=re.S)
    text = html.unescape(re.sub(r"<[^>]+>", " ", text))
    text = re.sub(r"[ \t]+", " ", text)
    text = re.sub(r"\n\s*\n+", "\n", text)
    print("=== XC API DOC ===")
    print(text[:24000])
except Exception as e:
    print("doc error", e)

key = None
for i in range(1, 9):
    v = os.environ.get(f"XC_CANDIDATE_{i}")
    print(f"candidate {i} set: {bool(v)}")
    if v and not key:
        key = v

if key:
    base = "https://xeno-canto.org/api/3/recordings?"
    try:
        d = json.loads(get(base + "query=" + urllib.parse.quote('sp:"erithacus rubecula" q:A') + "&per_page=50&key=" + key))
        print({k: v for k, v in d.items() if k != "recordings"})
        r = d["recordings"][0]
        print(json.dumps(r, indent=1)[:3500])
        for q in ["grp:birds", "grp:grasshoppers", "grp:bats", "grp:frogs", 'grp:"land mammals"', "grp:batsonly"]:
            try:
                dd = json.loads(get(base + "query=" + urllib.parse.quote(q) + "&per_page=50&key=" + key))
                print(q, dd.get("numRecordings"), dd.get("numSpecies"), dd.get("numPages"))
            except Exception as e:
                print(q, "err", e)
        try:
            dd = json.loads(get(base + "query=grp:birds&per_page=500&key=" + key))
            print("per_page 500 ->", len(dd["recordings"]))
        except Exception as e:
            print("per_page 500 err", e)
        f = r.get("file")
        if f:
            try:
                b = get(f if f.startswith("http") else "https:" + f, binary=True)
                print("file download without key OK bytes", len(b))
            except Exception as e:
                print("file download without key failed", e)
    except Exception as e:
        print("api error", type(e).__name__)
else:
    print("NO XC KEY FOUND under candidate names")

d = json.loads(get("https://api.inaturalist.org/v1/observations/species_counts?lat=52.46&lng=5.03&radius=15&iconic_taxa=Aves,Mammalia&per_page=3"))
print(json.dumps(d["results"][0], indent=1)[:2500])
