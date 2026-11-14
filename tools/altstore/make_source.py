#!/usr/bin/env python3
"""Writes an AltStore source (dist/altstore-source.json) for the WildID.ipa in dist/.

Add the source once in AltStore (Browse → Sources → +). AltStore then offers an Update button
whenever a newer version/build is published here. Usage: make_source.py <path to WildID.app> <ipa>
"""
import datetime as dt
import json
import os
import plistlib
import sys

BRANCH = os.environ.get("GITHUB_REF_NAME", "claude/festive-tesla-rhpbyd")
RAW = f"https://raw.githubusercontent.com/Youtube77077/WildID/{BRANCH}"

app, ipa = sys.argv[1], sys.argv[2]
info = plistlib.load(open(os.path.join(app, "Info.plist"), "rb"))
version = info.get("CFBundleShortVersionString", "1.0")
build = info.get("CFBundleVersion", "1")
size = os.path.getsize(ipa)
today = dt.date.today().isoformat()
description = ("Identify animals by sound and photo, collect them in your Wild Index, raise them as Wildlings, "
               "play mini-games and explore the wildlife around you.")
entry = {"version": version, "buildVersion": build, "date": today, "downloadURL": f"{RAW}/dist/WildID.ipa",
         "size": size, "localizedDescription": f"WildID {version} (build {build})", "minOSVersion": "17.0"}
source = {
    "name": "WildID",
    "identifier": "io.github.youtube77077.wildid.source",
    "subtitle": "Updates for WildID",
    "website": "https://github.com/Youtube77077/WildID",
    "apps": [{
        "name": "WildID",
        "bundleIdentifier": info.get("CFBundleIdentifier", "io.github.youtube77077.wildid"),
        "developerName": "WildID",
        "subtitle": "Discover the entire animal kingdom",
        "localizedDescription": description,
        "iconURL": f"{RAW}/WildID/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon.png",
        "tintColor": "1F6E5E",
        # Legacy (AltStore 1.x) fields plus the versions list newer AltStore reads.
        "version": version, "versionDate": today, "downloadURL": entry["downloadURL"], "size": size,
        "versionDescription": entry["localizedDescription"],
        "versions": [entry],
        "appPermissions": {"entitlements": [], "privacy": {
            "NSMicrophoneUsageDescription": "Sound ID listens for animal sounds.",
            "NSLocationWhenInUseUsageDescription": "Shows animals near you and places your catches on the map.",
        }},
    }],
    "news": [],
}
os.makedirs("dist", exist_ok=True)
json.dump(source, open("dist/altstore-source.json", "w"), indent=2)
print(json.dumps(entry, indent=2))
