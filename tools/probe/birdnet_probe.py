"""Research probe: inspects the published BirdNET V2.4 model files (Zenodo record 15050749)."""
import glob
import json
import os
import urllib.request
import zipfile

os.makedirs("bn", exist_ok=True)
rec = json.load(urllib.request.urlopen("https://zenodo.org/api/records/15050749"))
print("license:", rec["metadata"].get("license"))
for f in rec["files"]:
    print(f["key"], f["size"], f["links"]["self"])
for f in rec["files"]:
    k = f["key"]
    if k.endswith(".zip") and ("protobuf" in k.lower() or "tflite" in k.lower()):
        p = "bn/" + k
        urllib.request.urlretrieve(f["links"]["self"], p)
        with zipfile.ZipFile(p) as z:
            names = z.namelist()
            print("==", k, len(names))
            for n in names[:120]:
                print("  ", n)
            z.extractall("bn/" + k[:-4])

import tensorflow as tf  # noqa: E402

for sm in glob.glob("bn/**/saved_model.pb", recursive=True):
    d = os.path.dirname(sm)
    print("=== SavedModel", d)
    try:
        m = tf.saved_model.load(d)
        for name, fn in m.signatures.items():
            print(" sig", name, fn.structured_input_signature, fn.structured_outputs)
    except Exception as e:
        print(" load err", e)
    try:
        km = tf.keras.models.load_model(d, compile=False)
        km.summary(line_length=150)
        for layer in km.layers[:14]:
            print("LAYER", layer.name, type(layer).__name__, layer.get_config())
    except Exception as e:
        print(" keras load err", repr(e)[:800])

for tfl in glob.glob("bn/**/*.tflite", recursive=True):
    it = tf.lite.Interpreter(model_path=tfl)
    print("TFLITE", tfl, os.path.getsize(tfl),
          [(x["name"], x["shape"].tolist(), x["dtype"].__name__) for x in it.get_input_details()],
          [(x["name"], x["shape"].tolist()) for x in it.get_output_details()])
    try:
        ops = sorted({op["op_name"] for op in it._get_ops_details()})
        print("  ops", ops)
        if "MData" not in tfl:
            it.allocate_tensors()
            for t in it.get_tensor_details()[:60]:
                print("  T", t["index"], t["name"], t["shape"].tolist())
    except Exception as e:
        print(e)

labs = glob.glob("bn/**/*abels*.txt", recursive=True)[:3] + glob.glob("bn/**/en_us.txt", recursive=True)[:1]
for lab in labs:
    lines = open(lab, encoding="utf-8").read().splitlines()
    print("LABELS", lab, len(lines), lines[:3], lines[-15:])
