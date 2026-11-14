#!/usr/bin/env python3
"""Build a labelled, license-tracked animal sound dataset for training/validating WildID models.

Sources (each item keeps source, original id, URL, recordist, license and import date):
  * xeno-canto  — needs XENO_CANTO_API_KEY (birds, grasshoppers, bats, frogs, land mammals)
  * inaturalist — research-grade observation sounds, no key (all animal groups)

Pipeline per recording: download -> decode & resample to 48 kHz mono 16-bit WAV (ffmpeg) ->
reject corrupt/silent/too-short files -> de-duplicate by content hash -> optional log-mel
spectrogram PNG -> train/val split *by recordist* (prevents leakage between splits).

Licensing: only licenses that allow reuse are accepted. ND ("no derivatives") licenses are
excluded by default because training and spectrograms are derivative works. Commercial use is
NOT implied: NC licenses are kept, so the dataset is for non-commercial research.

Resumable: progress is tracked in <out>/manifest.csv; rerunning skips finished items.

Examples:
  python build_audio_dataset.py --taxa "Turdus merula,Erithacus rubecula" --source inaturalist --per-taxon 30
  python build_audio_dataset.py --place-lat 52.46 --place-lng 5.03 --top 50 --source both --spectrograms
"""
import argparse
import csv
import datetime as dt
import hashlib
import json
import os
import subprocess
import sys
import time
import urllib.parse
import urllib.request

UA = {"User-Agent": "WildID-dataset/1.0 (open-source research; github.com/Youtube77077/WildID)"}
FIELDS = ["uid", "source", "source_id", "taxon", "common_name", "group", "recordist", "license", "license_url",
          "page_url", "file_url", "sound_type", "quality", "country", "lat", "lng", "date", "imported",
          "wav_path", "seconds", "sha1", "split", "status"]
ALLOWED_INAT = {"cc0", "cc-by", "cc-by-sa", "cc-by-nc", "cc-by-nc-sa"}


def log(*a):
    print(*a, flush=True)


def get_json(url, pause=1.0, tries=5):
    for i in range(tries):
        try:
            time.sleep(pause)
            with urllib.request.urlopen(urllib.request.Request(url, headers=UA), timeout=90) as r:
                return json.load(r)
        except Exception:
            time.sleep(3 * (i + 1))
    raise RuntimeError("request failed after retries")


def license_ok_xc(lic_url, allow_nd):
    lic = (lic_url or "").lower()
    if not lic:
        return False
    if "-nd" in lic and not allow_nd:
        return False
    return "creativecommons.org" in lic


# ---------- sources ----------

def from_inaturalist(taxon, per_taxon):
    q = urllib.parse.urlencode({"taxon_name": taxon, "sounds": "true", "quality_grade": "research",
                                "sound_license": ",".join(sorted(ALLOWED_INAT)), "per_page": min(200, per_taxon * 2),
                                "order_by": "votes"})
    data = get_json("https://api.inaturalist.org/v1/observations?" + q)
    for o in data.get("results", []):
        t = o.get("taxon") or {}
        coords = (o.get("geojson") or {}).get("coordinates") or [None, None]
        for s in o.get("sounds", []):
            if not s.get("file_url") or (s.get("license_code") or "") not in ALLOWED_INAT:
                continue
            yield {"source": "inaturalist", "source_id": str(s["id"]), "taxon": t.get("name", taxon),
                   "common_name": t.get("preferred_common_name", ""), "group": t.get("iconic_taxon_name", ""),
                   "recordist": (o.get("user") or {}).get("login", ""), "license": s.get("license_code"),
                   "license_url": "", "page_url": o.get("uri", ""), "file_url": s["file_url"], "sound_type": "",
                   "quality": o.get("quality_grade", ""), "country": "", "lat": coords[1], "lng": coords[0],
                   "date": o.get("observed_on", "")}


def from_xeno_canto(taxon, per_taxon, allow_nd):
    key = os.environ.get("XENO_CANTO_API_KEY", "").strip()
    if not key:
        log("  (skipping Xeno-canto: XENO_CANTO_API_KEY not set)")
        return
    q = urllib.parse.urlencode({"query": f'sp:"{taxon.lower()}" q:">C"', "per_page": 100, "key": key})
    data = get_json("https://xeno-canto.org/api/3/recordings?" + q)
    for r in data.get("recordings", []):
        if r.get("_meta") or not r.get("file") or not license_ok_xc(r.get("lic"), allow_nd):
            continue
        lic = r.get("lic") or ""
        yield {"source": "xeno-canto", "source_id": "XC" + str(r["id"]), "taxon": f"{r.get('gen')} {r.get('sp')}",
               "common_name": r.get("en", ""), "group": r.get("grp", ""), "recordist": r.get("rec", ""),
               "license": lic.rstrip("/").split("/licenses/")[-1] if "/licenses/" in lic else lic,
               "license_url": ("https:" + lic) if lic.startswith("//") else lic,
               "page_url": ("https:" + r["url"]) if str(r.get("url", "")).startswith("//") else r.get("url", ""),
               "file_url": r["file"] if r["file"].startswith("http") else "https:" + r["file"],
               "sound_type": r.get("type", ""), "quality": r.get("q", ""), "country": r.get("cnt", ""),
               "lat": r.get("lat"), "lng": r.get("lon"), "date": r.get("date", "")}


# ---------- processing ----------

def decode_to_wav(src, dst, max_seconds):
    subprocess.run(["ffmpeg", "-v", "error", "-y", "-i", src, "-t", str(max_seconds), "-ac", "1", "-ar", "48000",
                    "-sample_fmt", "s16", dst], check=True, capture_output=True)


def wav_stats(path):
    import wave
    import numpy as np
    with wave.open(path) as w:
        n = w.getnframes()
        x = np.frombuffer(w.readframes(n), dtype=np.int16).astype("float32") / 32768
    return n / 48000.0, float(np.sqrt(np.mean(x ** 2)) if len(x) else 0.0)


def spectrogram_png(wav, png):
    """Log-mel spectrogram image (128 mel bands, 0-12 kHz) for inspection and CNN training."""
    import wave
    import numpy as np
    from PIL import Image
    with wave.open(wav) as w:
        x = np.frombuffer(w.readframes(w.getnframes()), dtype=np.int16).astype("float32") / 32768
    n_fft, hop = 1024, 480
    if len(x) < n_fft:
        return
    win = np.hanning(n_fft).astype("float32")
    frames = np.lib.stride_tricks.sliding_window_view(x, n_fft)[::hop] * win
    power = np.abs(np.fft.rfft(frames, axis=1)) ** 2
    freqs = np.fft.rfftfreq(n_fft, 1 / 48000)

    def hz_to_mel(f):
        return 2595 * np.log10(1 + f / 700)
    mels = np.linspace(hz_to_mel(150), hz_to_mel(12000), 130)
    edges = 700 * (10 ** (mels / 2595) - 1)
    fb = np.zeros((128, len(freqs)), dtype="float32")
    for i in range(128):
        l, c, r = edges[i], edges[i + 1], edges[i + 2]
        fb[i] = np.clip(np.minimum((freqs - l) / (c - l), (r - freqs) / (r - c)), 0, None)
    mel = 10 * np.log10(power @ fb.T + 1e-10)
    mel = np.clip((mel - mel.max() + 80) / 80, 0, 1)
    Image.fromarray((255 - mel.T[::-1] * 255).astype("uint8")).save(png)


def split_for(recordist, val_fraction):
    h = int(hashlib.sha1(recordist.encode("utf-8")).hexdigest(), 16) % 1000
    return "val" if h < val_fraction * 1000 else "train"


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--taxa", default="", help="comma separated scientific names")
    ap.add_argument("--place-lat", type=float)
    ap.add_argument("--place-lng", type=float)
    ap.add_argument("--top", type=int, default=30, help="with --place-*: most recorded species there")
    ap.add_argument("--iconic", default="Aves,Amphibia,Insecta,Mammalia")
    ap.add_argument("--source", choices=["inaturalist", "xeno-canto", "both"], default="both")
    ap.add_argument("--per-taxon", type=int, default=25)
    ap.add_argument("--max-seconds", type=int, default=60)
    ap.add_argument("--allow-nd", action="store_true")
    ap.add_argument("--val-fraction", type=float, default=0.2)
    ap.add_argument("--spectrograms", action="store_true")
    ap.add_argument("--out", default="datasets/audio")
    args = ap.parse_args()

    taxa = [t.strip() for t in args.taxa.split(",") if t.strip()]
    if args.place_lat is not None:
        q = urllib.parse.urlencode({"lat": args.place_lat, "lng": args.place_lng, "radius": 50, "sounds": "true",
                                    "quality_grade": "research", "iconic_taxa": args.iconic, "per_page": args.top})
        taxa += [r["taxon"]["name"] for r in get_json("https://api.inaturalist.org/v1/observations/species_counts?" + q)["results"]]
    if not taxa:
        sys.exit("give --taxa or --place-lat/--place-lng")

    os.makedirs(os.path.join(args.out, "raw"), exist_ok=True)
    manifest_path = os.path.join(args.out, "manifest.csv")
    done, hashes = {}, set()
    if os.path.exists(manifest_path):
        for row in csv.DictReader(open(manifest_path, newline="", encoding="utf-8")):
            done[row["uid"]] = row
            if row.get("sha1"):
                hashes.add(row["sha1"])
    out = open(manifest_path, "a", newline="", encoding="utf-8")
    writer = csv.DictWriter(out, fieldnames=FIELDS)
    if not done:
        writer.writeheader()

    for taxon in taxa:
        log(f"== {taxon}")
        items = []
        if args.source in ("inaturalist", "both"):
            items += list(from_inaturalist(taxon, args.per_taxon))
        if args.source in ("xeno-canto", "both"):
            items += list(from_xeno_canto(taxon, args.per_taxon, args.allow_nd) or [])
        kept = sum(1 for r in done.values() if r["taxon"].lower() == taxon.lower() and r["status"] == "ok")
        for item in items:
            if kept >= args.per_taxon:
                break
            uid = f"{item['source']}:{item['source_id']}"
            if uid in done:
                continue
            row = {**item, "uid": uid, "imported": dt.date.today().isoformat(), "status": "error"}
            slug = item["taxon"].replace(" ", "_")
            folder = os.path.join(args.out, row.get("split") or "", slug)
            raw = os.path.join(args.out, "raw", uid.replace(":", "_"))
            try:
                if not os.path.exists(raw):
                    with urllib.request.urlopen(urllib.request.Request(item["file_url"], headers=UA), timeout=120) as r, open(raw, "wb") as fh:
                        fh.write(r.read())
                    time.sleep(1.0)
                row["split"] = split_for(item["recordist"] or uid, args.val_fraction)
                folder = os.path.join(args.out, row["split"], slug)
                os.makedirs(folder, exist_ok=True)
                wav = os.path.join(folder, uid.replace(":", "_") + ".wav")
                decode_to_wav(raw, wav, args.max_seconds)
                seconds, rms = wav_stats(wav)
                sha1 = hashlib.sha1(open(wav, "rb").read()).hexdigest()
                if seconds < 1.0 or rms < 1e-4:
                    row["status"] = "rejected_short_or_silent"
                    os.remove(wav)
                elif sha1 in hashes:
                    row["status"] = "duplicate"
                    os.remove(wav)
                else:
                    hashes.add(sha1)
                    row.update({"wav_path": os.path.relpath(wav, args.out), "seconds": round(seconds, 2), "sha1": sha1, "status": "ok"})
                    if args.spectrograms:
                        spectrogram_png(wav, wav[:-4] + ".png")
                    kept += 1
            except Exception as e:  # corrupt download or undecodable file
                row["status"] = f"error: {type(e).__name__}"
            writer.writerow({k: row.get(k, "") for k in FIELDS})
            out.flush()
            done[uid] = row
            log(f"  {uid} -> {row['status']}")
    out.close()
    log("manifest:", manifest_path)


if __name__ == "__main__":
    main()
