#!/usr/bin/env python3
"""Xeno-canto metadata ingestion for WildID.

Pages through the Xeno-canto API v3 for every animal group it hosts, stores compact metadata for
each recording (with recordist, license and source preserved), and builds:

  data/xeno-canto/species/<first letter>/<genus_species>.json   best recordings per species
  data/xeno-canto/species_index.json                              species -> counts per quality

The app reads these public shards from GitHub, so the API key is only ever used here, read from
the XENO_CANTO_API_KEY environment variable (a GitHub Actions secret). It is never printed.

Fair use: one request per second, retries with backoff, and resumable checkpoints so an
interrupted run continues where it stopped instead of starting over.

Usage:
  XENO_CANTO_API_KEY=... python xeno_canto_ingest.py index --work work/xc [--max-minutes 300]
  python xeno_canto_ingest.py shards --work work/xc --out data/xeno-canto --per-species 10
"""
import argparse
import collections
import gzip
import json
import os
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

API = "https://xeno-canto.org/api/3/recordings"
GROUPS = ["birds", "grasshoppers", "bats", "frogs", "land mammals"]
KEEP = ["id", "gen", "sp", "ssp", "grp", "en", "rec", "cnt", "loc", "lat", "lon", "type", "sex", "stage",
        "q", "length", "file", "lic", "url", "date", "smp", "also", "method"]
UA = {"User-Agent": "WildID-ingest/1.0 (open-source; github.com/Youtube77077/WildID)"}


def log(*a):
    print(*a, flush=True)


def api_get(params, key, tries=6):
    url = API + "?" + urllib.parse.urlencode({**params, "key": key})
    for attempt in range(tries):
        try:
            with urllib.request.urlopen(urllib.request.Request(url, headers=UA), timeout=90) as r:
                return json.load(r)
        except urllib.error.HTTPError as e:
            # Never echo the URL (it contains the key).
            if e.code in (401, 403):
                sys.exit(f"Xeno-canto rejected the API key (HTTP {e.code}). Check the XENO_CANTO_API_KEY secret.")
            if e.code == 429 or e.code >= 500:
                time.sleep(min(120, 5 * 2 ** attempt))
                continue
            raise SystemExit(f"Xeno-canto error HTTP {e.code} for query {params.get('query')}")
        except (urllib.error.URLError, TimeoutError) as e:
            time.sleep(min(120, 5 * 2 ** attempt))
    raise SystemExit("Xeno-canto unreachable after retries")


def index(args):
    key = os.environ.get("XENO_CANTO_API_KEY", "").strip()
    if not key:
        sys.exit("XENO_CANTO_API_KEY is not set. Add it as a GitHub Actions repository secret named XENO_CANTO_API_KEY.")
    os.makedirs(args.work, exist_ok=True)
    state_path = os.path.join(args.work, "state.json")
    state = json.load(open(state_path)) if os.path.exists(state_path) else {"groups": {}}
    deadline = time.time() + args.max_minutes * 60
    for grp in GROUPS:
        g = state["groups"].setdefault(grp, {"next_page": 1, "pages": None, "done": False})
        if g["done"]:
            continue
        out_path = os.path.join(args.work, f"recordings_{grp.replace(' ', '_')}.ndjson.gz")
        while not g["done"]:
            if time.time() > deadline:
                json.dump(state, open(state_path, "w"))
                log("time budget reached; checkpoint saved, rerun to continue")
                return 0
            page = g["next_page"]
            data = api_get({"query": f'grp:"{grp}"', "per_page": args.per_page, "page": page}, key)
            g["pages"] = int(data.get("numPages", 1))
            recs = data.get("recordings", [])
            with gzip.open(out_path, "at", encoding="utf-8") as fh:
                for r in recs:
                    if r.get("_meta", {}).get("redacted_fields"):
                        continue  # restricted species: location and audio withheld by Xeno-canto
                    fh.write(json.dumps({k: r.get(k) for k in KEEP}, ensure_ascii=False) + "\n")
            log(f"{grp}: page {page}/{g['pages']} ({len(recs)} recordings)")
            g["next_page"] = page + 1
            g["done"] = page >= g["pages"]
            json.dump(state, open(state_path, "w"))
            time.sleep(1.0)
    log("index complete")
    return 0


def quality_rank(q):
    return {"A": 0, "B": 1, "C": 2, "D": 3, "E": 4}.get((q or "").strip()[:1], 5)


def shards(args):
    by_species = collections.defaultdict(dict)
    for name in os.listdir(args.work):
        if not name.startswith("recordings_"):
            continue
        with gzip.open(os.path.join(args.work, name), "rt", encoding="utf-8") as fh:
            for line in fh:
                r = json.loads(line)
                if not r.get("gen") or not r.get("sp") or (r.get("sp") or "").lower() in ("mystery", "sp."):
                    continue
                if not r.get("file"):
                    continue
                key = f"{r['gen']} {r['sp']}".lower()
                by_species[key][r["id"]] = r  # de-duplicates repeated pages
    os.makedirs(args.out, exist_ok=True)
    species_index = {}
    written = 0
    for sci, recs in by_species.items():
        recs = list(recs.values())
        counts = collections.Counter(quality_rank(r.get("q")) for r in recs)
        # Prefer quality, then variety of sound types, then shorter files (faster to stream).
        recs.sort(key=lambda r: (quality_rank(r.get("q")), float((r.get("length") or "9:59").replace(":", ".") or 9)))
        chosen, types = [], collections.Counter()
        for r in recs:
            t = (r.get("type") or "").split(",")[0].strip().lower()
            if types[t] >= max(2, args.per_species // 3) and len(recs) > args.per_species:
                continue
            chosen.append({k: r.get(k) for k in ["id", "gen", "sp", "en", "rec", "cnt", "loc", "type", "q", "length", "file", "lic", "url", "date"]})
            types[t] += 1
            if len(chosen) >= args.per_species:
                break
        slug = sci.replace(" ", "_")
        folder = os.path.join(args.out, "species", slug[0])
        os.makedirs(folder, exist_ok=True)
        with open(os.path.join(folder, slug + ".json"), "w", encoding="utf-8") as fh:
            json.dump({"scientific_name": sci, "source": "xeno-canto.org", "total_recordings": len(recs),
                       "recordings": chosen}, fh, ensure_ascii=False, separators=(",", ":"))
        species_index[sci] = {"en": recs[0].get("en"), "grp": recs[0].get("grp"), "n": len(recs),
                              "A": counts.get(0, 0), "B": counts.get(1, 0)}
        written += 1
    with open(os.path.join(args.out, "species_index.json"), "w", encoding="utf-8") as fh:
        json.dump({"generated": time.strftime("%Y-%m-%d"), "species": species_index}, fh, ensure_ascii=False, separators=(",", ":"))
    with open(os.path.join(args.out, "ATTRIBUTION.md"), "w") as fh:
        fh.write("# Xeno-canto metadata\n\nRecording metadata from https://xeno-canto.org (API v3). Every recording "
                 "remains © its recordist and is available under the license linked in its `lic` field. "
                 "Audio files are streamed from Xeno-canto; they are not stored in this repository.\n")
    log(f"wrote {written} species shards")


def main():
    ap = argparse.ArgumentParser()
    sub = ap.add_subparsers(dest="cmd", required=True)
    a = sub.add_parser("index")
    a.add_argument("--work", default="work/xc")
    a.add_argument("--per-page", type=int, default=500)
    a.add_argument("--max-minutes", type=float, default=300)
    b = sub.add_parser("shards")
    b.add_argument("--work", default="work/xc")
    b.add_argument("--out", default="data/xeno-canto")
    b.add_argument("--per-species", type=int, default=10)
    args = ap.parse_args()
    sys.exit(index(args) if args.cmd == "index" else shards(args))


if __name__ == "__main__":
    main()
