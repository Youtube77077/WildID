#!/usr/bin/env python3
"""Counts what WildID can show and identify, per animal group, from the live sources.

For each group:
  * iNaturalist taxonomy: active species and subspecies (what WildID can search and open)
  * species with at least one verifiable observation, with photos, with sounds
  * GBIF backbone: accepted species (proxy for "described species known to science")
  * BirdNET V2.4 sound classes per group (what Sound ID can name)

Writes tools/stats/reports/dataset_stats.{json,md}.
"""
import concurrent.futures as cf
import json
import os
import time
import urllib.parse
import urllib.request

UA = {"User-Agent": "WildID-stats/1.0 (open-source; github.com/Youtube77077/WildID)"}
GROUPS = [  # name, iNat taxon ids, GBIF names
    ("Birds", [3], ["Aves"]),
    ("Mammals", [40151], ["Mammalia"]),
    ("Reptiles", [26036], ["Reptilia", "Squamata", "Testudines", "Crocodylia"]),
    ("Amphibians", [20978], ["Amphibia"]),
    ("Fish (ray-finned + sharks/rays)", [47178, 47273], ["Actinopterygii", "Elasmobranchii"]),
    ("Insects", [47158], ["Insecta"]),
    ("Arachnids", [47119], ["Arachnida"]),
    ("Molluscs", [47115], ["Mollusca"]),
    ("Crustaceans", [85493], ["Malacostraca", "Maxillopoda", "Branchiopoda", "Ostracoda", "Copepoda", "Thecostraca", "Hexanauplia"]),
    ("All animals", [1], ["Animalia"]),
]
BACKBONE = "d7dddbf4-2cf0-4f39-9b2a-bb099caae36c"


def get(url, pause=1.05):
    for i in range(5):
        try:
            time.sleep(pause)
            with urllib.request.urlopen(urllib.request.Request(url, headers=UA), timeout=90) as r:
                return json.load(r)
        except Exception:
            time.sleep(3 * (i + 1))
    return {}


def inat(path, **p):
    return get("https://api.inaturalist.org/v1/" + path + "?" + urllib.parse.urlencode(p))


def inat_total(path, **p):
    return inat(path, per_page=0, **p).get("total_results", 0)


def gbif_key(name):
    d = get("https://api.gbif.org/v1/species/match?" + urllib.parse.urlencode({"name": name, "kingdom": "Animalia", "strict": "true"}), pause=0.2)
    return d.get("usageKey") if d.get("matchType") == "EXACT" else None


def gbif_species_count(names):
    total = 0
    for n in names:
        k = gbif_key(n)
        if not k:
            continue
        d = get("https://api.gbif.org/v1/species/search?" + urllib.parse.urlencode(
            {"rank": "SPECIES", "status": "ACCEPTED", "highertaxonKey": k, "datasetKey": BACKBONE, "limit": 0}), pause=0.2)
        total += d.get("count", 0)
        if n in ("Squamata", "Testudines", "Crocodylia") and total:
            pass
    return total


def birdnet_breakdown(labels_path):
    labels = [l.split("_", 1) for l in open(labels_path, encoding="utf-8").read().splitlines()]
    names = [l[0] for l in labels if " " in l[0] and len(l) == 2 and l[0] != l[1]]
    nonevent = len(labels) - len(names)

    def cls(name):
        d = get("https://api.gbif.org/v1/species/match?" + urllib.parse.urlencode({"name": name, "kingdom": "Animalia"}), pause=0.12)
        return d.get("class") or d.get("phylum") or "Unmatched"

    counts = {}
    with cf.ThreadPoolExecutor(max_workers=6) as ex:
        for c in ex.map(cls, names):
            counts[c] = counts.get(c, 0) + 1
    return {"total_classes": len(labels), "non_event_classes": nonevent, "by_class": dict(sorted(counts.items(), key=lambda kv: -kv[1]))}


def main():
    out = {"generated": time.strftime("%Y-%m-%d"), "groups": []}
    for name, ids, gnames in GROUPS:
        tid = ",".join(map(str, ids))
        row = {"group": name}
        row["inat_species"] = sum(inat_total("taxa", taxon_id=i, rank="species", is_active="true") for i in ids)
        row["inat_subspecies"] = sum(inat_total("taxa", taxon_id=i, rank="subspecies", is_active="true") for i in ids)
        row["species_with_observations"] = inat_total("observations/species_counts", taxon_id=tid, verifiable="true", hrank="species", lrank="species")
        row["species_with_photos"] = inat_total("observations/species_counts", taxon_id=tid, photos="true", verifiable="true", hrank="species", lrank="species")
        row["species_with_sounds"] = inat_total("observations/species_counts", taxon_id=tid, sounds="true", verifiable="true", hrank="species", lrank="species")
        row["gbif_accepted_species"] = gbif_species_count(gnames if name != "Reptiles" else ["Reptilia"]) or gbif_species_count(gnames[1:])
        print(json.dumps(row), flush=True)
        out["groups"].append(row)
    labels = os.path.join(os.path.dirname(__file__), "..", "..", "WildID", "Resources", "Models", "BirdNET_Labels_en.txt")
    out["birdnet"] = birdnet_breakdown(labels)
    print(json.dumps(out["birdnet"]), flush=True)
    os.makedirs("tools/stats/reports", exist_ok=True)
    json.dump(out, open("tools/stats/reports/dataset_stats.json", "w"), indent=1)
    with open("tools/stats/reports/dataset_stats.md", "w") as fh:
        fh.write(f"# WildID data coverage ({out['generated']})\n\n")
        fh.write("| Group | Species in app index (iNat) | Subspecies | Species with photos | Species with sounds | Species known to science (GBIF) |\n|---|---|---|---|---|---|\n")
        for r in out["groups"]:
            fh.write(f"| {r['group']} | {r['inat_species']:,} | {r['inat_subspecies']:,} | {r['species_with_photos']:,} | {r['species_with_sounds']:,} | {r['gbif_accepted_species']:,} |\n")
        b = out["birdnet"]
        fh.write(f"\n## Sound ID model (BirdNET V2.4)\n\n{b['total_classes']:,} classes ({b['non_event_classes']} non-animal/event classes).\n\n")
        for k, v in b["by_class"].items():
            fh.write(f"- {k}: {v:,}\n")


if __name__ == "__main__":
    main()
