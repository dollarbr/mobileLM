#!/usr/bin/env python3
"""Screen a GGUF for what this app can actually do with it, without downloading it.

The catalogue rule this exists for: a 404 and a useless model both surface only
at download time, and on a phone that is 450 MB and a minute. The second is
worse, because the download *succeeds* — the model loads, occupies the screen,
and does nothing. `jina-reranker-v1-tiny-en` is that case: 36 MB, half a second
to load, no output at all, because the conversion put the head at `cls.weight`
where llama.cpp looks for `cls.output` and dropped the `pooler.dense` the head
was trained against.

So: read the header, decide, and only then spend the bytes. A GGUF's metadata
and tensor directory are both at the front of the file — the directory is
descriptors, not data — so a few hundred KB is enough. A range request is the
whole trick.

The decision mirrors `jni_wrapper.cpp` exactly, and the architecture list is
*read out of the vendored llama.cpp* rather than typed here, so this cannot
drift from the binary it is screening for. A model this approves and the app
still refuses means the app changed, not the model, and that is worth finding
out here rather than on a phone.

    python3 tool/gguf-screen.py openjev/openjev-GGUF OpenJev-Q8_0.gguf
    python3 tool/gguf-screen.py --local model/gte-reranker-modernbert-base-Q8_0.gguf
    python3 tool/gguf-screen.py --batch candidates.txt      # "repo file" per line

Exit code is 0 whenever the run itself succeeded, whatever the verdicts — this
is a report, not a gate. Use `--strict` to fail on a REJECT, which is what the
catalogue addition checklist wants.
"""

import argparse
import os
import re
import shutil
import struct
import subprocess
import sys
import time
from urllib.error import URLError

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(HERE)
ARCH_SOURCE = os.path.join(
    REPO, "local_plugins/llama_flutter_android/android/src/main/cpp/llama.cpp/src/llama-arch.cpp"
)
HF = "https://huggingface.co"
# Enough for the header, the key/value block and the tensor directory of any
# model tested here. This has to cover the *vocabulary* block, because the tensor
# directory comes after it: a 256k-entry tokenizer is about 5 MB of token
# strings and another 4 MB of merges, so a small range never reaches the
# directory at all. 24 MB covers the largest vocabulary in circulation against
# 450 MB of model, which is the trade this tool exists to make.
HEADER_BYTES = 24 * 1024 * 1024


# ── the vendored architecture list ────────────────────────────────────────────
def known_arches():
    """Every `LLM_ARCH_*` name the linked llama.cpp will accept.

    Read from the vendored source, never typed. The GGUF's
    `general.architecture` is a string that has to match one of these or the
    loader does not know what to build — which is how `laya_english_q8_0`, whose
    architecture is `ggmlc`, fails: the head is missing *and* the architecture
    has never heard of. One name being absent here is the whole finding.
    """
    if not os.path.exists(ARCH_SOURCE):
        return None
    with open(ARCH_SOURCE, encoding="utf-8", errors="replace") as fh:
        text = fh.read()
    # { LLM_ARCH_BERT,             "bert"             },
    return set(re.findall(r'\{\s*LLM_ARCH_\w+,\s*"([\w\-]+)"\s*\}', text))


# ── GGUF header ───────────────────────────────────────────────────────────────
_ARR_ELEM = {
    0: "B", 1: "b", 2: "H", 3: "h", 4: "I", 5: "i", 6: "f",
    7: "?", 10: "Q", 11: "q", 12: "d",
}
_SCALAR_SIZE = {0: 1, 1: 1, 2: 2, 3: 2, 4: 4, 5: 4, 6: 4, 7: 1, 10: 8, 11: 8, 12: 8}

# Keys whose value is large, obvious, and of no use here. They are *skipped*, not
# decoded, which is the whole point: `tokenizer.ggml.tokens` holds one string per
# vocabulary entry — 250 002 of them on a Gemma-class model, about 5 MB — and
# `tokenizer.ggml.merges` is nearly as big. Decoding them to look at a tensor
# directory that sits past them is both slow and pointless, and a 4 MB range
# cannot even reach the directory: the first batch run failed on exactly this,
# `implausible array length 250002`, for every model with a large vocabulary.
_SKIP_KEYS = ("tokenizer.ggml.tokens", "tokenizer.ggml.merges",
              "tokenizer.ggml.token_type", "tokenizer.ggml.scores",
              "laya.temperature_by_options", "ggmlc.graph_spec")


class _R:
    def __init__(self, buf):
        self.b = buf
        self.i = 0

    def take(self, n):
        d = self.b[self.i:self.i + n]
        if len(d) < n:
            raise EOFError("header truncated at offset %d" % self.i)
        self.i += n
        return d

    def skip(self, n):
        if self.i + n > len(self.b):
            raise EOFError("header truncated at offset %d" % self.i)
        self.i += n

    def u8(self):
        return struct.unpack("<B", self.take(1))[0]

    def u32(self):
        return struct.unpack("<I", self.take(4))[0]

    def u64(self):
        return struct.unpack("<Q", self.take(8))[0]

    def s(self):
        n = self.u64()
        if n > (1 << 20):
            raise ValueError("implausible string length %d" % n)
        return self.take(n).decode("utf-8", "replace")


def _read_value(r, t):
    if t == 8:
        return r.s()
    if t == 9:
        et = r.u32()
        n = r.u64()
        if n > (1 << 28):
            raise ValueError("implausible array length %d" % n)
        return [_read_value(r, et) for _ in range(n)]
    if t not in _SCALAR_SIZE:
        raise ValueError("unknown gguf type %d" % t)
    return struct.unpack("<" + _ARR_ELEM[t], r.take(_SCALAR_SIZE[t]))[0]


def _skip_value(r, t):
    """Advance past a value without materialising it.

    The only array that matters to this screen is a short one, and a 250 002-entry
    string array is not short. Decoding is also the reason a 4 MB range failed:
    the bytes are simply not there, and reading them is wasted work either way.
    """
    if t == 8:
        n = r.u64()
        r.skip(n)
        return
    if t == 9:
        et = r.u32()
        n = r.u64()
        if et == 8:
            for _ in range(n):
                ln = r.u64()
                r.skip(ln)
        elif et == 9:
            raise ValueError("nested arrays are not expected in a GGUF key")
        else:
            r.skip(n * _SCALAR_SIZE[et])
        return
    if t not in _SCALAR_SIZE:
        raise ValueError("unknown gguf type %d" % t)
    r.skip(_SCALAR_SIZE[t])


def parse_header(buf):
    """Everything this app needs, from the front of the file."""
    r = _R(buf)
    if r.take(4) != b"GGUF":
        raise ValueError("not a GGUF")
    version = r.u32()
    n_tensors = r.u64()
    n_kv = r.u64()
    kv = {}
    for _ in range(n_kv):
        key = r.s()
        t = r.u32()
        if any(key.startswith(skip) for skip in _SKIP_KEYS):
            _skip_value(r, t)
            continue
        kv[key] = _read_value(r, t)
    tensors = {}
    for _ in range(n_tensors):
        name = r.s()
        nd = r.u32()
        dims = [r.u64() for _ in range(nd)]
        ttype = r.u32()
        r.u64()
        tensors[name] = (dims, ttype)
    arch = kv.get("general.architecture", "")
    return {
        "version": version,
        "kv": kv,
        "tensors": tensors,
        "arch": arch,
        "name": kv.get("general.name", ""),
        "tags": kv.get("general.tags", []) or [],
        "size_label": kv.get("general.size_label", ""),
        "declared_pooling": kv.get("%s.pooling_type" % arch),
        "labels": kv.get("%s.classifier.output_labels" % arch, []) or [],
        # The one hard requirement for a score, and the thing the jina
        # conversion got wrong by a name.
        "has_head": "cls.output.weight" in tensors,
        "head_dims": tensors.get("cls.output.weight", ([], None))[0],
        # The pooler projection. Its absence is why an injected head is garbage
        # even when the shape is right: the vector arriving at the head is not
        # the one the head was trained on.
        "pooler_dims": tensors.get("cls.weight", ([], None))[0],
        "has_pooler": "cls.weight" in tensors and len(tensors["cls.weight"][0]) == 2,
        "cls_norm": "cls.norm.weight" in tensors,
    }


# ── fetching ──────────────────────────────────────────────────────────────────
# `curl`, not `urllib`. Two reasons, and the first is the one that matters on a
# given machine: on this host `urllib` fails every request with
# `Name or service not known` while `curl` reaches the same URL, with no proxy
# set on either — the two resolve through different paths. The second is that
# `curl` is already how this repo checks a catalogue URL before committing one
# (`curl -sI … | grep content-length`), so a screen that has to agree with that
# check should not be using a different HTTP stack to get there.
_CURL = shutil.which("curl")


def _run(args, timeout=90, attempts=3):
    """`curl`, retried.

    A batch over a dozen repos hits DNS often enough that a single attempt makes
    the tool look broken rather than flaky — measured here: eight of eight
    consecutive requests failed with `curl exited 6` (couldn't resolve host) and
    the same URLs worked individually seconds later. Exit 6 and 7 are retryable;
    22 (`--fail`, a 404) is not, and retrying a 404 only hides it.
    """
    last = ""
    for attempt in range(attempts):
        proc = subprocess.run(args, capture_output=True, timeout=timeout)
        if proc.returncode == 0:
            return proc.stdout
        last = proc.stderr.decode("utf-8", "replace").strip() or "curl exited %d" % proc.returncode
        if proc.returncode not in (6, 7, 28, 35, 56):
            break
        if attempt + 1 < attempts:
            time.sleep(1.5 * (attempt + 1))
    raise URLError(last)


def fetch_head(url, timeout=90):
    if not _CURL:
        raise URLError("curl is not installed; this screen needs it for the range request")
    body = _run([_CURL, "-sL", "--fail", "-r", "0-%d" % (HEADER_BYTES - 1), url], timeout)
    if len(body) < 64:
        raise ValueError("got %d bytes — not a GGUF, or the range was refused" % len(body))
    return body


def remote_size(url, timeout=60):
    """The declared size, following the CDN redirect the way a download would."""
    head = _run([_CURL, "-sIL", url], timeout).decode("utf-8", "replace")
    for line in reversed(head.splitlines()):
        if line.lower().startswith("x-linked-size:"):
            return int(line.split(":", 1)[1].strip())
    for line in reversed(head.splitlines()):
        if line.lower().startswith("content-length:"):
            return int(line.split(":", 1)[1].strip())
    return 0


# ── the verdict ───────────────────────────────────────────────────────────────
POOLING = {0: "none", 1: "mean", 2: "cls", 3: "last", 4: "rank"}


def decide(info, arches):
    """Mirror of what the app will do, and the sentence explaining it."""
    arch = info["arch"]
    if arches is not None and arch not in arches:
        return "REJECT", (
            "architecture %r is not in the vendored llama.cpp. The loader has no "
            "graph for it, so this file does not load at all — the head being "
            "absent is the second problem, not the first." % arch
        )
    if info["has_head"]:
        shape = "x".join(str(d) for d in info["head_dims"]) or "?"
        extra = "" if info["has_pooler"] else (
            "  The head is there but the pooler projection is not, so the vector "
            "reaching it is not the one it was trained on — this is the case that "
            "produces a number in (-1, 1) that ranks plausibly."
        )
        if info["declared_pooling"] is None:
            return "RERANK", (
                "cls.output.weight [%s] is present and llama.cpp infers RANK for an "
                "encoder with a head, so /v1/rerank and /v1/classify will work. The "
                "file declares no pooling type; the inference is ours and is "
                "reported as such.%s" % (shape, extra)
            )
        return "RERANK", (
            "cls.output.weight [%s] is present, declared pooling %s.%s"
            % (shape, POOLING.get(info["declared_pooling"], info["declared_pooling"]), extra)
        )
    if info["declared_pooling"] is not None:
        p = POOLING.get(info["declared_pooling"], info["declared_pooling"])
        if p in ("mean", "cls", "last"):
            return "EMBED", (
                "no classification head, declared pooling %s: /v1/embeddings will "
                "work and return %s." % (p, "a vector" if p != "mean" else "a mean-pooled vector")
            )
        return "EMBED", "no head, declared pooling %s: /v1/embeddings will work." % p
    return "REJECT", (
        "no cls.output.weight and no declared pooling type, so there is neither a "
        "logit to return nor a vector to pool. It loads and produces nothing. %s"
        % ("The file's own tags call it: " + ", ".join(info["tags"]) + "." if info["tags"]
           else "The file carries no general.tags to say what it intended to be.")
    )


# ── output ────────────────────────────────────────────────────────────────────
def report(label, info, size, arches):
    verdict, why = decide(info, arches)
    print("── %s" % label)
    if size:
        print("   size            %d bytes (%.1f MB)" % (size, size / 1e6))
    print("   architecture    %r%s" % (
        info["arch"],
        "" if arches is None or info["arch"] in arches else "   ← NOT IN THE VENDORED LLAMA.CPP"))
    print("   general.name    %r" % info["name"])
    print("   general.tags    %s" % (", ".join(info["tags"]) or "(none)"))
    print("   tensors         %d" % len(info["tensors"]))
    print("   pooling         %s" % (
        "declared %s" % POOLING.get(info["declared_pooling"], info["declared_pooling"])
        if info["declared_pooling"] is not None else "(not declared)"))
    print("   head            %s" % (
        "cls.output.weight %s" % (info["head_dims"] or "(shape unknown)") if info["has_head"]
        else "ABSENT"))
    print("   pooler          %s" % (
        "cls.weight %s" % info["pooler_dims"] if info["has_pooler"] else "ABSENT"))
    print("   labels          %s" % (", ".join(str(x) for x in info["labels"]) or "(none)"))
    print("   → %-6s %s" % (verdict, why))
    print()
    return verdict


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("targets", nargs="*", help="'repo file' pairs")
    ap.add_argument("--local", action="append", default=[], help="a local .gguf to read in full")
    ap.add_argument("--batch", help="file with one 'repo file' pair per line")
    ap.add_argument("--strict", action="store_true",
                    help="exit 1 if any target is REJECTed")
    args = ap.parse_args()

    arches = known_arches()
    if arches is None:
        print("warning: could not read %s; architecture names will not be checked"
              % ARCH_SOURCE, file=sys.stderr)
    else:
        print("read %d architecture names from the vendored llama.cpp\n" % len(arches))

    targets = list(args.targets)
    if args.batch:
        with open(args.batch, encoding="utf-8") as fh:
            targets += [line.split() for line in fh
                        if line.strip() and not line.startswith("#")]

    verdicts = []
    for local in args.local:
        with open(local, "rb") as fh:
            buf = fh.read(HEADER_BYTES)
        verdicts.append(report(local, parse_header(buf), os.path.getsize(local), arches))

    for t in targets:
        repo, name = t if isinstance(t, list) else t.split(None, 1)
        url = "%s/%s/resolve/main/%s" % (HF, repo, name)
        try:
            buf = fetch_head(url)
            size = remote_size(url)
            verdicts.append(report("%s / %s" % (repo, name), parse_header(buf), size, arches))
        except (URLError, OSError, ValueError, EOFError) as exc:
            print("── %s / %s\n   FAILED: %s\n" % (repo, name, exc))
            verdicts.append("ERROR")

    if args.strict and "REJECT" in verdicts:
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
