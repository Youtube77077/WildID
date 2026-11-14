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


HOP = 48000             # 1 s, as in the app
THRESHOLDS = [0.08, 0.15, 0.3, 0.5]   # Maximum, Sensitive (default), Balanced, Conservative


def window_scores(audio_it, samples, max_seconds=60):
    """Sigmoid scores per 3 s window (1 s hop) of the first 60 s: array [windows, classes]."""
    samples = samples[: int(max_seconds * 48000)]
    win = 144000
    if len(samples) < win:
        samples = np.pad(samples, (0, win - len(samples)))
    rows = []
    for start in range(0, len(samples) - win + 1, HOP):
        logits = run_tflite(audio_it, samples[start:start + win][None, :])[0]
        rows.append(1 / (1 + np.exp(-logits)))
    return np.array(rows)


def score_recording(audio_it, samples, max_seconds=60):
    return window_scores(audio_it, samples, max_seconds).max(axis=0)


def app_accepts(windows, threshold):
    """The app's auto-add rule per class: above threshold in >= 2 windows, or one window >= max(0.7, t+0.2)."""
    hits = (windows >= threshold).sum(axis=0)
    return (hits >= 2) | (windows.max(axis=0) >= max(0.7, threshold + 0.2))


def faint_and_windy(samples, seed):
    """Stress test: the animal 30 dB quieter (peak −30 dBFS) under strong synthetic wind
    (low-passed random walk, most energy below 100 Hz) plus light microphone hiss."""
    rng = np.random.default_rng(seed)
    peak = np.abs(samples).max() or 1.0
    animal = samples / peak * 10 ** (-30 / 20)
    from scipy.signal import lfilter
    wind = lfilter([0.02], [1, -0.9995], rng.uniform(-1, 1, len(samples))).astype(np.float32) * 0.5
    hiss = rng.uniform(-1, 1, len(samples)).astype(np.float32) * 0.002
    return (animal + wind + hiss).astype(np.float32)


def rank_of(probs, truth):
    order = np.argsort(-probs)
    return int(np.where(order == truth)[0][0]) + 1


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
            wins = window_scores(audio_it, samples)
            probs = wins.max(axis=0)
            noisy_wins = window_scores(audio_it, faint_and_windy(samples[: 60 * 48000], seed=int(snd["id"])))
            probs_noisy = noisy_wins.max(axis=0)
            coords = (o.get("geojson") or {}).get("coordinates") or [None, None]
            lng, lat = coords[0], coords[1]
            when = o.get("observed_on") or dt.date.today().isoformat()
            d = dt.date.fromisoformat(when[:10])
            occ = None
            if lat is not None:
                occ = run_tflite(meta_it, np.array([[lat, lng, birdnet_week(d)]], dtype=np.float32))[0]
            truth = sci_to_idx[t["name"].lower()]
            order = np.argsort(-probs)
            def loc_filter(pr):
                out = pr.copy()
                if occ is not None:
                    out[(occ < 0.03) & (pr < 0.9)] = 0
                return out
            filtered = loc_filter(probs)
            forder = np.argsort(-filtered)
            others = np.arange(len(probs)) != truth
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
                "noisy_truth_score": float(probs_noisy[truth]),
                "noisy_rank_filtered": rank_of(loc_filter(probs_noisy), truth),
            })
            keep = (occ >= 0.03) if occ is not None else np.ones_like(probs, dtype=bool)   # location filter
            for cond, w in (("clean", wins), ("faint_wind", noisy_wins)):
                for th in THRESHOLDS:
                    acc = app_accepts(w, th) & (keep | (w.max(axis=0) >= 0.9))
                    results[-1][f"{cond}_added_{th}"] = bool(acc[truth])
                    results[-1][f"{cond}_other_species_added_{th}"] = int((acc & others).sum())
            n += 1
            r = results[-1]
            print(f"{t['name']:<32} rank {r['rank']:>4}  filtered {r['rank_filtered']:>4}  p={r['truth_score']:.2f}  "
                  f"faint+wind p={r['noisy_truth_score']:.2f} rank {r['noisy_rank_filtered']}  top1={r['top1']}")

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
        "faint_wind_top1_filtered": float(np.mean([r["noisy_rank_filtered"] == 1 for r in results])),
        "faint_wind_top5_filtered": float(np.mean([r["noisy_rank_filtered"] <= 5 for r in results])),
    }
    sweep = []
    for cond in ("clean", "faint_wind"):
        for t in THRESHOLDS:
            sweep.append({"condition": cond, "threshold": t,
                          "true_species_added": float(np.mean([r[f"{cond}_added_{t}"] for r in results])),
                          "other_species_added_per_recording": float(np.mean([r[f"{cond}_other_species_added_{t}"] for r in results]))})
    summary["threshold_sweep"] = sweep
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
        fh.write("\nScores are the maximum over 3 s windows (1 s hop) of the first 60 s, as in the app. "
                 "`faint_wind` is a stress test: each recording is turned 30 dB quieter (peak −30 dBFS) and mixed with "
                 "strong synthetic wind and hiss. Recordings may contain other species, so 'other species' include real "
                 "background animals, not only mistakes.\n\n")
        fh.write("## Sensitivity settings (app rule: ≥ 2 windows above threshold, or one ≥ max(0.7, t+0.2); location filter on)\n\n"
                 "| Condition | Threshold | True species added | Other species added per recording |\n|---|---|---|---|\n")
        names = {0.08: "Maximum", 0.15: "Sensitive (default)", 0.3: "Balanced", 0.5: "Conservative"}
        for row in sweep:
            fh.write(f"| {row['condition']} | {row['threshold']} {names[row['threshold']]} | {row['true_species_added']:.1%} | "
                     f"{row['other_species_added_per_recording']:.2f} |\n")
        fh.write("\n")
        fh.write("## Per recording\n\n| Species | Rank | Rank (filtered) | p(true) | Faint+wind p | Faint+wind rank | Top-1 | License |\n|---|---|---|---|---|---|---|---|\n")
        for r in results:
            fh.write(f"| *{r['species']}* | {r['rank']} | {r['rank_filtered']} | {r['truth_score']:.2f} | {r['noisy_truth_score']:.2f} | "
                     f"{r['noisy_rank_filtered']} | {r['top1'].split('_')[-1]} | {r['license']} |\n")
    print(json.dumps(summary, indent=1))


if __name__ == "__main__":
    main()
