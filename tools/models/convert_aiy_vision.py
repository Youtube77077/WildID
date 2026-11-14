#!/usr/bin/env python3
"""Convert Google's AIY Vision species classifiers (TF Hub, Apache 2.0) to Core ML.

  birds_V1   — 965 bird species (+ background)      labelmap: aiy_birds_V1_labelmap.csv
  insects_V1 — 1,021 insect species (+ background)   labelmap: aiy_insects_V1_labelmap.csv

Input: 224x224 RGB image scaled to [0, 1]. Output: class probabilities.
Usage: python convert_aiy_vision.py --out WildID/Resources/Models --work work/aiy
"""
import argparse
import csv
import io
import json
import os
import shutil
import sys
import tarfile
import urllib.request

import numpy as np

MODELS = {
    "birds": ("https://tfhub.dev/google/aiy/vision/classifier/birds_V1/1?tf-hub-format=compressed",
              "https://www.gstatic.com/aihub/tfhub/labelmaps/aiy_birds_V1_labelmap.csv", "PhotoBirds"),
    "insects": ("https://tfhub.dev/google/aiy/vision/classifier/insects_V1/1?tf-hub-format=compressed",
                "https://www.gstatic.com/aihub/tfhub/labelmaps/aiy_insects_V1_labelmap.csv", "PhotoInsects"),
}


def fetch(url):
    req = urllib.request.Request(url, headers={"User-Agent": "WildID-model-conversion/1.0"})
    with urllib.request.urlopen(req, timeout=300) as r:
        return r.read()


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", required=True)
    ap.add_argument("--work", default="work/aiy")
    args = ap.parse_args()
    import coremltools as ct
    import tensorflow as tf
    import tensorflow_hub as hub

    os.makedirs(args.work, exist_ok=True)
    report = {}
    for key, (model_url, labels_url, name) in MODELS.items():
        mdir = os.path.join(args.work, key)
        if not os.path.exists(os.path.join(mdir, "saved_model.pb")):
            data = fetch(model_url)
            os.makedirs(mdir, exist_ok=True)
            with tarfile.open(fileobj=io.BytesIO(data), mode="r:gz") as t:
                t.extractall(mdir)
        print(key, "files:", os.listdir(mdir), flush=True)
        labels_csv = fetch(labels_url).decode("utf-8")
        rows = list(csv.DictReader(io.StringIO(labels_csv)))
        names = [r.get("name") or list(r.values())[1] for r in rows]
        print(key, len(names), "labels; e.g.", names[:3], flush=True)

        module = hub.load(mdir)
        sig = None
        if hasattr(module, "signatures") and module.signatures:
            sig = module.signatures.get("default") or list(module.signatures.values())[0]
        if sig is None:
            fn = tf.function(lambda x: module(x), input_signature=[tf.TensorSpec([1, 224, 224, 3], tf.float32)])
            cf = fn.get_concrete_function()
        else:
            print(key, "signature", sig.structured_input_signature, sig.structured_outputs, flush=True)
            in_name = list(sig.structured_input_signature[1].keys())[0]
            out_key = list(sig.structured_outputs.keys())[0]

            @tf.function(input_signature=[tf.TensorSpec([1, 224, 224, 3], tf.float32, name="image")])
            def fn(x):
                return sig(**{in_name: x})[out_key]
            cf = fn.get_concrete_function()

        x = np.random.default_rng(0).random((1, 224, 224, 3)).astype(np.float32)
        ref = cf(tf.constant(x)).numpy()
        print(key, "output shape", ref.shape, "sum", float(ref.sum()), flush=True)
        is_prob = abs(float(ref.sum()) - 1) < 0.05

        mlmodel = ct.convert(
            [cf], source="tensorflow",
            inputs=[ct.ImageType(name="image", shape=(1, 224, 224, 3), scale=1 / 255.0, color_layout=ct.colorlayout.RGB)],
            convert_to="mlprogram", minimum_deployment_target=ct.target.iOS16,
            compute_precision=ct.precision.FLOAT16,
        )
        spec = mlmodel.get_spec()
        ct.utils.rename_feature(spec, spec.description.output[0].name, "scores")
        mlmodel = ct.models.MLModel(spec, weights_dir=mlmodel.weights_dir)
        mlmodel.short_description = f"Google AIY Vision {key} classifier ({len(names)} classes), Apache 2.0. Output: {'probabilities' if is_prob else 'logits'}."
        mlmodel.license = "Apache 2.0"
        path = os.path.join(args.out, f"{name}.mlpackage")
        shutil.rmtree(path, ignore_errors=True)
        mlmodel.save(path)
        with open(os.path.join(args.out, f"{name}_Labels.txt"), "w", encoding="utf-8") as fh:
            fh.write("\n".join(names))
        report[key] = {"classes": len(names), "output_is_probability": is_prob}
        if sys.platform == "darwin":
            from PIL import Image
            img = Image.fromarray((x[0] * 255).astype(np.uint8))
            y = ct.models.MLModel(path, compute_units=ct.ComputeUnit.CPU_ONLY).predict({"image": img})["scores"]
            report[key]["top1_match"] = bool(int(np.argmax(y)) == int(np.argmax(ref)))
    json.dump(report, open(os.path.join(args.out, "photo_models_report.json"), "w"), indent=1)
    print(json.dumps(report, indent=1))


if __name__ == "__main__":
    main()
