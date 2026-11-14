#!/usr/bin/env python3
"""Evaluate BirdNET V2.4 (the model WildID ships) on real, openly licensed field recordings.

Data: research-grade iNaturalist observations with sounds (CC0 / CC BY / CC BY-NC / CC BY-SA /
CC BY-NC-SA) of the most-recorded bird species around a location. Each recording is labelled
with its observation's community-verified species.

Method (mirrors the app): 48 kHz mono, 3 s windows with 1.5 s overlap, sigmoid of logits,
species score = max over windows. Reported: top-1 / top-5 accuracy, detection rate at the
app's "Balanced" threshold (0.5), and the effect of BirdNET's location/week filter.

Usage:
  python evaluate_birdnet.py --lat 52.46 --lng 5.03 --species 40 --per-species 4 --out tools/eval/reports
Requires: tensorflow, numpy, ffmpeg on PATH. Resumable: downloads are cached in --work.
"""
import argparse
import datetime as dt
import json
import os
import subprocess
import sys
import time
import urllib.parse
import urllib.request
import zipfile

import numpy as np

UA = {"User-Agent": "WildID-evaluation/1.0 (open-source research; github.com/Youtube77077/WildID)"}
OPEN_LICENSES = "cc0,cc-by,cc-by-nc,cc-by-sa,cc-by-nc-sa"


def get_json(url, tries=4):
    for i in range(tries):
        try:
            with urllib.request.urlopen(urllib.request.Request(url, headers=UA), timeout=60) as r:
                return json.load(r)
        except Exception as e:  # noqa
            if i == tries - 1:
                raise
            time.sleep(2 * (i + 1))


def inat(path, **params):
    time.sleep(1.0)  # iNaturalist asks for ~1 request/second
    return get_json("https://api.inaturalist.org/v1/" + path + "?" + urllib.parse.urlencode(params))


def load_models(work):
    import tensorflow as tf
    os.makedirs(work, exist_ok=True)
    rec = get_json("https://zenodo.org/api/records/15050749")
    for f in rec["files"]:
        if f["key"] == "BirdNET_v2.4_tflite_fp16.zip":
            dest = os.path.join(work, f["key"])
            if not os.path.exists(dest):
                urllib.request.urlretrieve(f["links"]["self"], dest)
            with zipfile.ZipFile(dest) as z:
                z.extractall(os.path.join(work, "tflite"))
    base = os.path.join(work, "tflite")
    audio = tf.lite.Interpreter(model_path=os.path.join(base, "audio-model-fp16.tflite"), num_threads=4)
    audio.allocate_tensors()
    meta = tf.lite.Interpreter(model_path=os.path.join(base, "meta-model.tflite"))
    meta.allocate_tensors()
    labels = open(os.path.join(base, "labels", "en_us.txt"), encoding="utf-8").read().splitlines()
    return audio, meta, labels


def run_tflite(it, x):
    inp = it.get_input_details()[0]
    it.set_tensor(inp["index"], x.astype(np.float32))
    it.invoke()
    return it.get_tensor(it.get_output_details()[0]["index"])


def birdnet_week(date):
    return (date.month - 1) * 4 + min(4, int(np.ceil(date.day / 7.0)))


def decode(path):
    """Decode any audio file to 48 kHz mono float32 with ffmpeg."""
    out = subprocess.run(["ffmpeg", "-v", "quiet", "-i", path, "-ac", "1", "-ar", "48000", "-f", "f32le", "-"],
                         capture_output=True, check=True).stdout
    return np.frombuffer(out, dtype=np.float32)


def score_recording(audio_it, samples, max_seconds=60):
    samples = samples[: int(max_seconds * 48000)]
    win, hop = 144000, 72000
    if len(samples) < win:
        samples = np.pad(samples, (0, win - len(samples)))
    best = None
    for start in range(0, len(samples) - win + 1, hop):
        logits = run_tflite(audio_it, samples[start:start + win][None, :])[0]
        p = 1 / (1 + np.exp(-logits))
        best = p if best is None else np.maximum(best, p)
    return best


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--lat", type=float, default=52.46)
    ap.add_argument("--lng", type=float, default=5.03)
    ap.add_argument("--radius", type=int, default=50)
    ap.add_argument("--species", type=int, default=40)
    ap.add_argument("--per-species", type=int, default=4)
    ap.add_argument("--work", default="work/eval")
    ap.add_argument("--out", default="tools/eval/reports")
    args = ap.parse_args()

    audio_it, meta_it, labels = load_models(args.work)
    sci_to_idx = {l.split("_", 1)[0].lower(): i for i, l in enumerate(labels)}

    # 1) Species most often recorded with sound near the location.
    sc = inat("observations/species_counts", lat=args.lat, lng=args.lng, radius=args.radius, taxon_id=3,
              sounds="true", quality_grade="research", per_page=args.species * 2)
    species = [r["taxon"] for r in sc["results"]]
    species = [t for t in species if t["name"].lower() in sci_to_idx][: args.species]
    print(f"{len(species)} species with BirdNET labels")

    cache = os.path.join(args.work, "audio")
    os.makedirs(cache, exist_ok=True)
    results = []
    for t in species:
        obs = inat("observations", taxon_id=t["id"], sounds="true", quality_grade="research",
                   sound_license=OPEN_LICENSES, per_page=args.per_species * 2, order_by="votes")
        n = 0
        for o in obs["results"]:
            snd = next((s for s in o.get("sounds", []) if s.get("file_url")), None)
            if not snd or n >= args.per_species:
                continue
            url = snd["file_url"]
            ext = os.path.splitext(url.split("?")[0])[1] or ".mp3"
            path = os.path.join(cache, f"{snd['id']}{ext}")
            try:
                if not os.path.exists(path):
                    req = urllib.request.Request(url, headers=UA)
                    with urllib.request.urlopen(req, timeout=120) as r, open(path, "wb") as fh:
                        fh.write(r.read())
                samples = decode(path)
            except Exception as e:  # noqa
                print("skip", url, e)
                continue
            if len(samples) < 48000:
                continue
            probs = score_recording(audio_it, samples)
            coords = (o.get("geojson") or {}).get("coordinates") or [None, None]
            lng, lat = coords[0], coords[1]
            when = o.get("observed_on") or dt.date.today().isoformat()
            d = dt.date.fromisoformat(when[:10])
            occ = None
            if lat is not None:
                occ = run_tflite(meta_it, np.array([[lat, lng, birdnet_week(d)]], dtype=np.float32))[0]
            truth = sci_to_idx[t["name"].lower()]
            order = np.argsort(-probs)
            filtered = probs.copy()
            if occ is not None:
                filtered[(occ < 0.03) & (probs < 0.9)] = 0
            forder = np.argsort(-filtered)
            results.append({
                "species": t["name"], "common": t.get("preferred_common_name"), "observation": o["uri"],
                "license": snd.get("license_code"), "attribution": snd.get("attribution"),
                "seconds": round(len(samples) / 48000, 1),
                "truth_score": float(probs[truth]),
                "top1": labels[order[0]], "top1_score": float(probs[order[0]]),
                "rank": int(np.where(order == truth)[0][0]) + 1,
                "rank_filtered": int(np.where(forder == truth)[0][0]) + 1,
                "false_at_0.5": int(((probs >= 0.5) & (np.arange(len(probs)) != truth)).sum()),
                "false_at_0.5_filtered": int(((filtered >= 0.5) & (np.arange(len(probs)) != truth)).sum()),
            })
            n += 1
            r = results[-1]
            print(f"{t['name']:<32} rank {r['rank']:>4}  filtered {r['rank_filtered']:>4}  p={r['truth_score']:.2f}  top1={r['top1']}")

    if not results:
        sys.exit("no recordings evaluated")
    ranks = np.array([r["rank"] for r in results])
    franks = np.array([r["rank_filtered"] for r in results])
    truth_scores = np.array([r["truth_score"] for r in results])
    summary = {
        "date": dt.date.today().isoformat(),
        "location": {"lat": args.lat, "lng": args.lng, "radius_km": args.radius},
        "recordings": len(results),
        "species": len({r["species"] for r in results}),
        "top1": float(np.mean(ranks == 1)),
        "top5": float(np.mean(ranks <= 5)),
        "top1_with_location_filter": float(np.mean(franks == 1)),
        "top5_with_location_filter": float(np.mean(franks <= 5)),
        "detected_at_0.5": float(np.mean(truth_scores >= 0.5)),
        "detected_at_0.3": float(np.mean(truth_scores >= 0.3)),
        "mean_false_species_at_0.5": float(np.mean([r["false_at_0.5"] for r in results])),
        "mean_false_species_at_0.5_filtered": float(np.mean([r["false_at_0.5_filtered"] for r in results])),
    }
    os.makedirs(args.out, exist_ok=True)
    json.dump({"summary": summary, "results": results}, open(os.path.join(args.out, "birdnet_eval.json"), "w"), indent=1)
    with open(os.path.join(args.out, "birdnet_eval.md"), "w") as fh:
        fh.write("# BirdNET V2.4 evaluation on real recordings\n\n")
        fh.write(f"Run {summary['date']} · {summary['recordings']} research-grade iNaturalist recordings of "
                 f"{summary['species']} bird species recorded within {args.radius} km of ({args.lat}, {args.lng}).\n\n")
        fh.write("| Metric | Value |\n|---|---|\n")
        for k, v in summary.items():
            if isinstance(v, float):
                fh.write(f"| {k} | {v:.1%} |\n" if "mean" not in k else f"| {k} | {v:.2f} |\n")
        fh.write("\nScores are the maximum over 3 s windows (1.5 s hop) of the first 60 s, as in the app. "
                 "Recordings may contain other species, so 'false' detections include real background birds.\n\n")
        fh.write("## Per recording\n\n| Species | Rank | Rank (filtered) | p(true) | Top-1 | License |\n|---|---|---|---|---|---|\n")
        for r in results:
            fh.write(f"| *{r['species']}* | {r['rank']} | {r['rank_filtered']} | {r['truth_score']:.2f} | {r['top1'].split('_')[-1]} | {r['license']} |\n")
    print(json.dumps(summary, indent=1))


if __name__ == "__main__":
    main()
