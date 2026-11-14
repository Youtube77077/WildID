#!/usr/bin/env python3
"""Convert the BirdNET V2.4 acoustic model and its location/season meta-model to Core ML.

Source: BirdNET V2.4, Zenodo record 15050749 (Cornell Lab of Ornithology & Chemnitz
University of Technology), licensed CC BY-NC-SA 4.0. The converted models keep that license.

Why surgery is needed: the acoustic model computes its own spectrogram with the TensorFlow
`RFFT` op, which Core ML cannot represent (it has no complex dtype). We replace every
`RFFT -> ComplexAbs` pair with an exactly equivalent real-valued DFT:
    |X_k| = sqrt( (sum_n x_n cos(2*pi*k*n/N))^2 + (sum_n x_n sin(2*pi*k*n/N))^2 )
implemented with BatchMatMul against constant cosine/sine bases. The rewritten graph is
validated against the original in TensorFlow, then converted with coremltools and (on macOS)
validated again with Core ML predictions.

Usage: python convert_birdnet.py --out WildID/Resources/Models --work work/
"""
import argparse
import json
import os
import shutil
import sys
import urllib.request
import zipfile

import numpy as np

ZENODO_RECORD = "15050749"


def log(*a):
    print(*a, flush=True)


def download(work):
    os.makedirs(work, exist_ok=True)
    rec = json.load(urllib.request.urlopen(f"https://zenodo.org/api/records/{ZENODO_RECORD}"))
    wanted = {"BirdNET_v2.4_protobuf.zip", "BirdNET_v2.4_tflite_fp16.zip"}
    for f in rec["files"]:
        if f["key"] in wanted:
            dest = os.path.join(work, f["key"])
            if not os.path.exists(dest):
                log("downloading", f["key"], f["size"])
                urllib.request.urlretrieve(f["links"]["self"], dest)
            with zipfile.ZipFile(dest) as z:
                z.extractall(os.path.join(work, f["key"][:-4]))
    return (os.path.join(work, "BirdNET_v2.4_protobuf"), os.path.join(work, "BirdNET_v2.4_tflite_fp16"))


def freeze(saved_model_dir, signature):
    import tensorflow as tf
    from tensorflow.python.framework.convert_to_constants import convert_variables_to_constants_v2

    m = tf.saved_model.load(saved_model_dir)
    fn = m.signatures[signature]
    frozen = convert_variables_to_constants_v2(fn)
    gd = frozen.graph.as_graph_def()
    in_name = frozen.inputs[0].name.split(":")[0]
    out_name = frozen.outputs[0].name.split(":")[0]
    return gd, in_name, out_name, fn


def consumers(gd):
    cons = {}
    for n in gd.node:
        for i in n.input:
            src = i.lstrip("^").split(":")[0]
            cons.setdefault(src, []).append(n)
    return cons


def describe_frontend(gd):
    """Print nodes in graph order up to the first Conv2D, for documentation/debugging."""
    for n in gd.node:
        if n.op == "Const":
            continue
        log(f"  node {n.op:<18} {n.name}  <- {list(n.input)[:3]}")
        if n.op in ("Conv2D",):
            break


def rewrite_rfft(gd, in_name, sample_input):
    """Replace RFFT+ComplexAbs with real DFT matmuls. Returns a new GraphDef."""
    import tensorflow as tf
    from tensorflow.core.framework import graph_pb2, node_def_pb2, attr_value_pb2

    cons = consumers(gd)
    rffts = [n for n in gd.node if n.op == "RFFT"]
    log("RFFT nodes:", [n.name for n in rffts])
    if not rffts:
        return gd

    # Determine static frame length of each RFFT input by running the original graph.
    g = tf.Graph()
    with g.as_default():
        tf.compat.v1.import_graph_def(gd, name="")
    shapes, fft_lens = {}, {}
    with tf.compat.v1.Session(graph=g) as sess:
        for r in rffts:
            t_in = g.get_tensor_by_name(r.input[0] if ":" in r.input[0] else r.input[0] + ":0")
            val = sess.run(t_in, {in_name + ":0": sample_input})
            shapes[r.name] = val.shape
            fl = sess.run(g.get_tensor_by_name((r.input[1] if ":" in r.input[1] else r.input[1] + ":0")))
            fft_lens[r.name] = int(np.array(fl).reshape(-1)[0])
            log(f"  {r.name}: input shape {val.shape}, fft_length {fft_lens[r.name]}")

    remove = set()
    new_nodes = []

    def const_node(name, arr):
        nd = node_def_pb2.NodeDef(name=name, op="Const")
        nd.attr["dtype"].CopyFrom(attr_value_pb2.AttrValue(type=tf.float32.as_datatype_enum))
        nd.attr["value"].CopyFrom(attr_value_pb2.AttrValue(tensor=tf.make_tensor_proto(arr.astype(np.float32))))
        return nd

    def op_node(name, op, inputs, **attrs):
        nd = node_def_pb2.NodeDef(name=name, op=op)
        nd.input.extend(inputs)
        nd.attr["T"].CopyFrom(attr_value_pb2.AttrValue(type=tf.float32.as_datatype_enum))
        for k, v in attrs.items():
            nd.attr[k].CopyFrom(attr_value_pb2.AttrValue(b=v))
        return nd

    for r in rffts:
        users = cons.get(r.name, [])
        supported = [c for c in users if c.op in ("ComplexAbs", "Cast", "Real")]
        if len(supported) != len(users) or not users:
            raise SystemExit(f"Unsupported RFFT consumers for {r.name}: {[(c.op, c.name) for c in users]}")
        L = shapes[r.name][-1]
        F = fft_lens[r.name]
        K = F // 2 + 1
        n = np.arange(L)[:, None].astype(np.float64)
        k = np.arange(K)[None, :].astype(np.float64)
        valid = (n < F).astype(np.float64)
        base = r.name + "_dft"
        # TF's rfft uses exp(-i*2*pi*k*n/N): Re = sum x*cos, Im = -sum x*sin.
        cos_b = np.cos(2 * np.pi * n * k / F) * valid
        new_nodes += [
            const_node(base + "/cos", cos_b),
            op_node(base + "/re", "BatchMatMulV2", [r.input[0], base + "/cos"], adj_x=False, adj_y=False),
        ]
        need_mag = any(c.op == "ComplexAbs" for c in users)
        if need_mag:
            # Scale bases by 1/S so squared terms stay inside float16 range; undo after sqrt.
            S = float(F)
            new_nodes += [
                const_node(base + "/cos_s", cos_b / S),
                const_node(base + "/sin_s", np.sin(2 * np.pi * n * k / F) * valid / S),
                const_node(base + "/scale", np.array(S)),
                op_node(base + "/re_s", "BatchMatMulV2", [r.input[0], base + "/cos_s"], adj_x=False, adj_y=False),
                op_node(base + "/im_s", "BatchMatMulV2", [r.input[0], base + "/sin_s"], adj_x=False, adj_y=False),
                op_node(base + "/re2", "Square", [base + "/re_s"]),
                op_node(base + "/im2", "Square", [base + "/im_s"]),
                op_node(base + "/sum", "AddV2", [base + "/re2", base + "/im2"]),
                op_node(base + "/mag", "Sqrt", [base + "/sum"]),
            ]
        remove.add(r.name)
        for c in users:
            remove.add(c.name)
            # Keep each consumer's name so downstream nodes are untouched.
            if c.op == "ComplexAbs":
                new_nodes.append(op_node(c.name, "Mul", [base + "/mag", base + "/scale"]))
            else:  # Cast(complex->float) and Real both yield the real part
                new_nodes.append(op_node(c.name, "Identity", [base + "/re"]))

    out = graph_pb2.GraphDef()
    out.versions.CopyFrom(gd.versions)
    out.library.CopyFrom(gd.library)
    for nd in gd.node:
        if nd.name not in remove:
            out.node.append(nd)
    out.node.extend(new_nodes)
    return out


def run_graph(gd, in_name, out_name, x):
    import tensorflow as tf

    g = tf.Graph()
    with g.as_default():
        tf.compat.v1.import_graph_def(gd, name="")
    with tf.compat.v1.Session(graph=g) as sess:
        return sess.run(out_name + ":0", {in_name + ":0": x})


def frontend_node_names(gd):
    """Names of all nodes upstream of the first Conv2D (the spectrogram front end)."""
    by_name = {n.name: n for n in gd.node}
    first_conv = next(n for n in gd.node if n.op == "Conv2D")
    seen, stack = set(), [first_conv.input[0].split(":")[0]]
    while stack:
        nm = stack.pop().lstrip("^")
        if nm in seen or nm not in by_name:
            continue
        seen.add(nm)
        stack.extend(i.split(":")[0] for i in by_name[nm].input)
    return seen


def test_audio(work):
    """A deterministic synthetic test signal (chirps + noise) plus any real WAV if present."""
    sr = 48000
    t = np.arange(144000) / sr
    rng = np.random.default_rng(42)
    x = 0.3 * np.sin(2 * np.pi * (2500 + 1500 * np.sin(2 * np.pi * 3 * t)) * t)
    x += 0.02 * rng.standard_normal(t.shape)
    samples = {"synthetic": x.astype(np.float32)[None, :]}
    real = os.path.join(work, "test.wav")
    if os.path.exists(real):
        import wave
        with wave.open(real) as w:
            assert w.getframerate() == 48000 and w.getnchannels() == 1 and w.getsampwidth() == 2
            a = np.frombuffer(w.readframes(w.getnframes()), dtype=np.int16).astype(np.float32) / 32768.0
        if len(a) >= 144000:
            # pick the loudest 3 s window
            hop = 24000
            best = max(range(0, len(a) - 144000 + 1, hop), key=lambda s: float(np.mean(a[s:s + 144000] ** 2)))
            samples["real"] = a[best:best + 144000][None, :]
    return samples


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", required=True)
    ap.add_argument("--work", default="work")
    ap.add_argument("--testdata", default=None, help="where to write XCTest vectors")
    args = ap.parse_args()

    import coremltools as ct
    import tensorflow as tf

    pb_dir, tfl_dir = download(args.work)
    os.makedirs(args.out, exist_ok=True)

    # ---------- labels ----------
    labels_src = os.path.join(tfl_dir, "labels", "en_us.txt")
    labels = open(labels_src, encoding="utf-8").read().splitlines()
    assert len(labels) == 6522, len(labels)
    shutil.copy(labels_src, os.path.join(args.out, "BirdNET_Labels_en.txt"))

    # ---------- acoustic model ----------
    gd, in_name, out_name, fn = freeze(os.path.join(pb_dir, "audio-model"), "basic")
    log("audio model input", in_name, "output", out_name)
    describe_frontend(gd)
    samples = test_audio(args.work)
    x0 = samples["synthetic"]
    ref = {k: run_graph(gd, in_name, out_name, v) for k, v in samples.items()}
    for k, v in ref.items():
        log(f"reference[{k}] scores range {v.min():.3f}..{v.max():.3f}; top5",
            [(labels[i], round(float(v[0, i]), 3)) for i in np.argsort(-v[0])[:5]])

    gd2 = rewrite_rfft(gd, in_name, x0)
    for k, v in samples.items():
        y = run_graph(gd2, in_name, out_name, v)
        diff = float(np.max(np.abs(y - ref[k])))
        log(f"rewritten graph [{k}] max |diff| = {diff:.6f}")
        assert diff < 1e-2, "DFT rewrite changed the model output"

    frontend = frontend_node_names(gd2)
    log("front-end nodes kept in float32:", len(frontend))

    def fp16_selector(op):
        # Keep the spectrogram front end in float32 for numerical fidelity.
        base = op.name
        for _ in range(3):
            if base in frontend:
                return False
            if "_" not in base:
                break
            base = base.rsplit("_", 1)[0]
        return op.op_type != "const"

    audio_pb = os.path.join(args.work, "audio_rewritten.pb")
    with open(audio_pb, "wb") as fh:
        fh.write(gd2.SerializeToString())
    mlmodel = ct.convert(
        audio_pb,
        source="tensorflow",
        inputs=[ct.TensorType(name=in_name, shape=(1, 144000), dtype=np.float32)],
        outputs=[ct.TensorType(name=out_name)],
        convert_to="mlprogram",
        minimum_deployment_target=ct.target.iOS16,
        compute_precision=ct.transform.FP16ComputePrecision(op_selector=fp16_selector),
    )
    mlmodel.short_description = "BirdNET V2.4 acoustic classifier (6,522 classes, 3 s @ 48 kHz). CC BY-NC-SA 4.0."
    mlmodel.author = "BirdNET team (Cornell Lab of Ornithology, Chemnitz University of Technology); converted for WildID"
    mlmodel.license = "CC BY-NC-SA 4.0"
    mlmodel.version = "2.4"
    spec = mlmodel.get_spec()
    ct.utils.rename_feature(spec, in_name, "audio")
    ct.utils.rename_feature(spec, spec.description.output[0].name, "scores")
    mlmodel = ct.models.MLModel(spec, weights_dir=mlmodel.weights_dir)
    audio_path = os.path.join(args.out, "BirdNETAudio.mlpackage")
    shutil.rmtree(audio_path, ignore_errors=True)
    mlmodel.save(audio_path)
    log("saved", audio_path)

    # ---------- meta model ----------
    mgd, m_in, m_out, _ = freeze(os.path.join(pb_dir, "meta-model"), "serving_default")
    meta_pb = os.path.join(args.work, "meta_frozen.pb")
    with open(meta_pb, "wb") as fh:
        fh.write(mgd.SerializeToString())
    meta = ct.convert(
        meta_pb,
        source="tensorflow",
        inputs=[ct.TensorType(name=m_in, shape=(1, 3), dtype=np.float32)],
        outputs=[ct.TensorType(name=m_out)],
        convert_to="mlprogram",
        minimum_deployment_target=ct.target.iOS16,
    )
    from coremltools.optimize.coreml import OpLinearQuantizerConfig, OptimizationConfig, linear_quantize_weights
    meta = linear_quantize_weights(meta, OptimizationConfig(global_config=OpLinearQuantizerConfig(mode="linear_symmetric", weight_threshold=2048)))
    mspec = meta.get_spec()
    ct.utils.rename_feature(mspec, mspec.description.input[0].name, "location")
    ct.utils.rename_feature(mspec, mspec.description.output[0].name, "occurrence")
    meta = ct.models.MLModel(mspec, weights_dir=meta.weights_dir)
    meta.short_description = "BirdNET V2.4 species occurrence model: input [latitude, longitude, week(1-48 or -1)]. CC BY-NC-SA 4.0."
    meta.license = "CC BY-NC-SA 4.0"
    meta_path = os.path.join(args.out, "BirdNETMeta.mlpackage")
    shutil.rmtree(meta_path, ignore_errors=True)
    meta.save(meta_path)
    log("saved", meta_path)

    # ---------- Core ML validation (macOS only) ----------
    report = {"labels": len(labels)}
    if sys.platform == "darwin":
        cm = ct.models.MLModel(audio_path, compute_units=ct.ComputeUnit.CPU_ONLY)
        for k, v in samples.items():
            y = cm.predict({"audio": v})["scores"]
            diff = float(np.max(np.abs(y - ref[k])))
            top_ref = list(np.argsort(-ref[k][0])[:5])
            top_cm = list(np.argsort(-y[0])[:5])
            log(f"Core ML [{k}] max |diff| {diff:.4f}; top5 ref {top_ref} coreml {top_cm}")
            report[f"audio_{k}_maxdiff"] = diff
            report[f"audio_{k}_top1_match"] = bool(top_ref[0] == top_cm[0])
        mm = ct.models.MLModel(meta_path, compute_units=ct.ComputeUnit.CPU_ONLY)
        import tensorflow as tf  # noqa
        mt = tf.saved_model.load(os.path.join(pb_dir, "meta-model")).signatures["serving_default"]
        q = np.array([[52.46, 5.03, 46]], dtype=np.float32)  # Monnickendam, mid-November
        tref = list(mt(tf.constant(q)).values())[0].numpy()
        ycm = mm.predict({"location": q})["occurrence"]
        report["meta_maxdiff"] = float(np.max(np.abs(ycm - tref)))
        report["meta_species_above_0.03_nl_nov"] = int((tref[0] > 0.03).sum())
        log("meta", report["meta_maxdiff"], report["meta_species_above_0.03_nl_nov"])
        if args.testdata:
            os.makedirs(args.testdata, exist_ok=True)
            k = "real" if "real" in samples else "synthetic"
            samples[k].astype("<f4").tofile(os.path.join(args.testdata, "birdnet_input.f32"))
            top = list(np.argsort(-ref[k][0])[:5])
            json.dump({"source": k, "top5": [int(i) for i in top],
                       "top5_labels": [labels[i] for i in top],
                       "top5_scores": [float(ref[k][0, i]) for i in top],
                       "meta_query": q[0].tolist(),
                       "meta_top5": [int(i) for i in np.argsort(-tref[0])[:5]]},
                      open(os.path.join(args.testdata, "birdnet_expected.json"), "w"), indent=1)
    json.dump(report, open(os.path.join(args.out, "conversion_report.json"), "w"), indent=1)
    log(json.dumps(report, indent=1))


if __name__ == "__main__":
    main()
