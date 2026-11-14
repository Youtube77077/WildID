# Data sources assessed for WildID

WildID only uses data whose access method and license allow it. This page records what was
evaluated and why each source is (or is not) integrated. Terms change — re-check each source's
current terms before bulk use.

## Integrated

| Source | What WildID uses | Access | License / terms | Where |
|---|---|---|---|---|
| **BirdNET V2.4** (Cornell Lab of Ornithology, TU Chemnitz) | Acoustic classifier (6,522 classes) + location/week occurrence model, converted to Core ML | Zenodo record 15050749 (SavedModel + TFLite) | CC BY-NC-SA 4.0 — non-commercial, attribution, share-alike | `tools/models/convert_birdnet.py`, `WildID/Audio/BirdNETClassifier.swift` |
| **Xeno-canto** API v3 | Recording metadata (species, type, quality, place, recordist, license, file URL) → per-species shards; optional live queries with the user's own key | REST, key required on every call; ~1 request/s fair use; restricted species have location and audio redacted | Per recording Creative Commons; recordist credit required | `tools/ingest/xeno_canto_ingest.py`, `.github/workflows/xeno-canto.yml`, `XenoCantoAPI` |
| **iNaturalist** API v1 | Taxonomy & names (synonyms resolved), photos, sounds, research-grade observations, species counts by place/month, weekly histograms, similar species, map point and range tiles | Public REST, no key for reads; ≤ ~60 requests/min recommended; bulk downloads should use the iNaturalist Open Data on AWS instead of the API | Photos/sounds individually licensed (shown with attribution); WildID requests only openly licensed sounds | `WildID/Services/INaturalist.swift`, eval + dataset tools |
| **GBIF** | Backbone taxonomy matching, occurrence counts, occurrence density map tiles | Public REST + map tile API | Occurrence data CC0 / CC BY / CC BY-NC per dataset; tiles free to use with attribution | `GBIFAPI` |
| **Wikipedia** (English) | Lead summary and sections mapped to Description, Habitat, Diet, Behaviour, Reproduction, Lifespan, Conservation | MediaWiki Action API (`prop=extracts`) | CC BY-SA 4.0 — linked and attributed on every page | `WikipediaAPI` |
| **Wikidata** | Length, height, wingspan, mass, life expectancy, longest recorded lifespan | SPARQL endpoint | CC0 | `WikidataAPI` |
| **Apple SoundAnalysis** | Built-in ~300-class sound classifier for non-bird animal sounds (mostly group level) | iOS framework | Apple SDK | `AppleSoundClassifier.swift` |
| **Apple Vision** | On-device image classification to find the kind of animal in a photo | iOS framework | Apple SDK | `PhotoIDView.swift` |
| **Apple MapKit** | Maps, satellite imagery, geocoding, place search | iOS framework | Apple SDK | Map features |

## Evaluated, not integrated (yet)

| Source | Why not (now) | Path forward |
|---|---|---|
| **Macaulay Library** (Cornell) | Huge, high-quality archive, but no open bulk API; media are generally licensed for personal/educational viewing and reuse needs permission | Link out from species pages; request research access for training data |
| **iNaturalist computer-vision API** | Not offered for third-party apps; requires an authenticated session and is governed by iNaturalist's terms | Use the iNaturalist Open Data dataset (AWS) to train an own photo model offline |
| **AmphibiaWeb** | Excellent species accounts; sound coverage is limited and not bulk-downloadable via an open API | Candidate for amphibian text descriptions (check license per account) |
| **Animal Sound Archive (Tierstimmenarchiv, Berlin)** | Large archive; parts are published via GBIF/European data portals with mixed licenses | Ingest the openly licensed subset via GBIF media search |
| **BioSounds / Bioacoustica** | Research platforms with variable per-collection access | Evaluate collection by collection |
| **Watkins Marine Mammal Sound Database** | Free for personal/academic use, no API, redistribution restricted | Possible future marine-mammal evaluation set (not redistributed) |
| **Google Perch** | Bird/bioacoustics embedding model (Apache 2.0) — needs an additional classifier head and TF-Lite/Core ML conversion | Candidate for a second on-device model and for transfer learning to non-bird taxa |
| **Catalogue of Life** | Authoritative checklist; iNaturalist and GBIF already align to it closely enough for WildID's needs | Use for name reconciliation if conflicts appear |

## Recognition roadmap (honest status)

- **Birds:** species-level, on device (BirdNET), validated on real recordings (`tools/eval/reports`).
- **Frogs, insects, mammals:** species-level only for the BirdNET classes that cover them; otherwise
  group-level via Apple's classifier. The dataset builder (`tools/ingest/build_audio_dataset.py`)
  produces license-clean, recordist-split training data to train dedicated models.
- **Photos:** group-level recognition on device + user confirmation against local species. A
  species-level photo model can be added as a Core ML package without changing the app's flow.
