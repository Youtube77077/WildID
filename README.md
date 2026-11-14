# WildID

**Discover the entire animal kingdom.** WildID is a native iPhone app (Swift / SwiftUI) for identifying, collecting and exploring animals — inspired by the interaction patterns of Merlin Bird ID, extended from birds to all animals.

- **Sound ID** – live microphone identification with a real scrolling spectrogram (FFT), detections appearing as they happen, a yellow highlight for newly heard species, sessions up to **3 hours** that keep running with the screen locked, and **Save** to keep the whole recording (size shown in MB/GB, deletable).
- **Wild Index** – your Pokémon-style collection: one card per species, a journal of every catch (date, place, method, confidence, your photo, the sound clip you caught), rarity, achievements, and "yet to catch nearby" silhouettes. Detections are added automatically and a small **New Animal** pop-up slides in without interrupting recording.
- **Map** – Apple Maps (MapKit) with your catches as photo pins (clustered), recent community sightings, an all-observations layer, species ranges and satellite view.
- **Explore** – animals recorded near you this season (or anywhere you pick on the map), plus a worldwide search across every animal on iNaturalist.
- **Species pages** – photo gallery, sounds (Xeno-canto + iNaturalist) with recordist and license, weekly seasonality near you, range map vs. occurrence records (kept separate), size/mass/lifespan (Wikidata), description/habitat/diet/behaviour/reproduction/conservation (Wikipedia), full taxonomy, conservation status, similar species, sources.
- **Photo ID** and **Step by Step** guided identification.

> WildID needs an internet connection for species data, photos and maps (as requested: "only work online"). Your Wild Index, catches, clips, saved recordings and previously opened species pages stay available offline.

---

## Install it on your iPhone (no App Store needed)

You need a **Mac with Xcode 16 or newer** (free from the Mac App Store) and an **Apple ID**. A free Apple ID works; apps installed with a free account must be re-installed every 7 days. A paid Apple Developer Program membership ($99/year) removes that limit.

1. **Get the code**
   ```bash
   git clone https://github.com/Youtube77077/WildID.git
   cd WildID
   git checkout claude/festive-tesla-rhpbyd   # or main once merged
   open WildID.xcodeproj
   ```
2. **Sign in to Xcode**: *Xcode › Settings › Accounts › +* → Apple ID.
3. **Set signing**: in the project navigator select **WildID** (blue icon) → target **WildID** → **Signing & Capabilities** → tick *Automatically manage signing* → choose your **Team** (e.g. "Your Name (Personal Team)").
4. **Make the bundle ID unique** (Apple requires this). Either edit `Config/WildID.xcconfig`:
   ```
   WILDID_BUNDLE_IDENTIFIER = com.yourname.wildid
   ```
   or create `Config/Local.xcconfig` (git-ignored) containing that line and `DEVELOPMENT_TEAM = YOURTEAMID`.
5. **Connect your iPhone** with a cable (or same Wi-Fi after pairing once), unlock it and tap *Trust*.
6. **Enable Developer Mode on the iPhone** (iOS 16+): *Settings › Privacy & Security › Developer Mode* → on → restart.
7. In Xcode's toolbar pick your iPhone as the run destination and press **▶ Run** (⌘R).
8. First launch with a free account: on the iPhone go to *Settings › General › VPN & Device Management* → your Apple ID → **Trust**. Then open WildID.
9. Allow **Microphone** (Sound ID), **Location** (nearby animals, filtering, map) and **Camera/Photos** (Photo ID) when asked.

Requirements: iOS 17.0 or later, iPhone. App size ≈ 50 MB (most of it is the BirdNET sound model).

### Alternative: unsigned build from CI

Every push builds the app on GitHub Actions (`iOS build & tests`). The run uploads `WildID-unsigned.ipa` as an artifact. That file is **not installable as-is**; tools such as Sideloadly or AltStore can re-sign it with your Apple ID. Xcode (above) is the reliable route.

---

## How identification works (and its limits)

| Feature | What it uses | Coverage |
|---|---|---|
| Sound ID – species | **BirdNET V2.4** acoustic model (Cornell Lab of Ornithology & TU Chemnitz) converted to Core ML, on-device, 3 s windows every 1.5 s | 6,522 classes: mostly birds worldwide, plus some frogs, insects and mammals |
| Sound ID – location filter | **BirdNET meta-model**: species expected at your latitude/longitude in the current week (48-week calendar) | Same classes |
| Sound ID – other animals | **Apple SoundAnalysis** built-in classifier (iOS, zero app size) | Dogs, cats, livestock, frogs, crickets/insects, owls, crows, ducks, whales… mostly *groups*, shown as "Possible: …" and never auto-added |
| Photo ID | **Apple Vision** on-device image classification → mapped to a scientific group → species of that group recorded near you (iNaturalist) to compare and confirm | Common animal types; species chosen by you, never guessed from the photo alone |
| Step by Step | A question tree (shape, size, legs, wings…) mapped to real taxa → species recorded at the place/season you choose | All animal groups |

**Validation.** `tools/models/convert_birdnet.py` checks that the Core ML model reproduces TensorFlow's output (top-1 identical on a real Eurasian Blackbird recording, max logit difference ≈ 0.07). `tools/eval/evaluate_birdnet.py` (workflow *Evaluate BirdNET on real recordings*) scores the model on research-grade iNaturalist recordings of birds around Monnickendam and writes `tools/eval/reports/birdnet_eval.md`. Unit tests run the bundled model on the real recording on the iOS Simulator.

**Honest limits.** Bird song identification is mature; insects, bats (ultrasonic — phones can't hear them) and marine mammals are only partly covered; group-level detections are not species identifications; photo identification relies on you to confirm the species. Rarity labels describe how often a species is *recorded* within 50 km on iNaturalist, not its population.

---

## Architecture

```
WildID/
  App/            WildIDApp, RootView (5 tabs + New Animal toast + listening pill), AppEnvironment, Router, NearbyStore
  Audio/          AudioCaptureEngine (AVAudioEngine → 48 kHz mono + streaming AAC file, interruptions, 3 h cap)
                  Spectrogram (vDSP FFT, adaptive noise floor, CADisplayLink renderer)
                  BirdNETClassifier (Core ML audio + meta model, location/week filter)
                  AppleSoundClassifier (SoundAnalysis), SoundIDSession (pipeline, detections, auto-catch, save)
                  AudioPlayer (reference sounds, clips, recordings)
  Services/       HTTPClient (rate limits, disk cache, offline fallback), INaturalist, EncyclopediaSources
                  (Wikipedia, Wikidata, GBIF, Xeno-canto), Collection (Wild Index manager, taxon resolver, toasts),
                  PlatformServices (location, connectivity, settings, Keychain)
  Models/         SwiftData: WildIndexEntry, Catch, SavedRecording, RecordingDetection; AnimalGroup
  Features/       Home, Identify (Sound ID, sessions, Photo ID, Step by Step), Map, WildIndex, Explore, Species, Settings
  Design/         Theme, components, cached remote images, New Animal toast
  Resources/      Assets, BirdNETAudio.mlpackage, BirdNETMeta.mlpackage, labels (generated by CI)
WildIDTests/      Unit tests (+ reference vectors produced by the conversion workflow)
tools/
  models/         BirdNET → Core ML converter (RFFT rewritten as DFT matmuls, validated), reports
  eval/           Accuracy evaluation on real recordings
  ingest/         Xeno-canto metadata ingestion (resumable) and audio dataset builder (licenses, resampling,
                  de-duplication, spectrograms, recordist-based splits)
.github/workflows iOS build & tests · model conversion · evaluation · Xeno-canto index
```

**Data layer.** Species identity is the iNaturalist taxon (stable IDs, synonyms resolved); classifier labels are matched by scientific name and cached. Everything is fetched on demand from public APIs — no huge static files in the app. Responses are cached on disk so opened pages work offline. Map overlays (observation points, ranges, GBIF density) are rendered server-side as tiles, which keeps the app light.

**Privacy.** Only coordinates and species names are sent to the wildlife APIs — never your identity. Sensitive species are excluded from community map markers (`geoprivacy=open`, `taxon_geoprivacy=open`), and Xeno-canto withholds restricted-species locations.

---

## Secrets (Xeno-canto API key)

- The key is **never** in the app, Info.plist, or repository.
- GitHub Actions reads it from the repository secret **`XENO_CANTO_API_KEY`** (*Settings › Secrets and variables › Actions › New repository secret*). If you stored it under another name or in a GitHub *Environment*, add/rename it to `XENO_CANTO_API_KEY` as a repository secret — the *Xeno-canto index* workflow skips with a notice until it exists.
- The workflow builds `data/xeno-canto/species/*.json` (best recordings per species with recordist + license); the app reads these public files, so it needs no key.
- Optionally you can paste your own key in the app (*Settings › Xeno-canto*); it is stored in the iPhone Keychain only.
- See `.env.example` for local tooling.

## Running the tooling locally

```bash
python3 -m venv .venv && source .venv/bin/activate
pip install -r tools/models/requirements.txt          # macOS for Core ML validation
python tools/models/convert_birdnet.py --out WildID/Resources/Models --work work
pip install "tensorflow==2.17.0" "numpy<2" && brew install ffmpeg
python tools/eval/evaluate_birdnet.py --lat 52.46 --lng 5.03
export XENO_CANTO_API_KEY=...                           # never commit it
python tools/ingest/xeno_canto_ingest.py index && python tools/ingest/xeno_canto_ingest.py shards
python tools/ingest/build_audio_dataset.py --place-lat 52.46 --place-lng 5.03 --top 30 --source both --spectrograms
```

## Data sources & licenses

- **BirdNET V2.4** models — CC BY-NC-SA 4.0 (non-commercial; converted models in `WildID/Resources/Models` keep this license). https://birdnet.cornell.edu
- **Xeno-canto** recordings — each under its own Creative Commons license, credited to its recordist.
- **iNaturalist** — taxonomy, photos and sounds (each item shown with author and license), observations, range tiles.
- **GBIF** — backbone matching and occurrence density maps.
- **Wikipedia** (CC BY-SA 4.0) and **Wikidata** (CC0).
- Test recording: iNaturalist observation 110684075, © Codrin Bucur, CC BY.

WildID is an independent, non-commercial project and is not affiliated with the Cornell Lab of Ornithology or Merlin Bird ID. App source code: MIT (see `LICENSE`).
