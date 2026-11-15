#!/usr/bin/env python3
"""Read every workflow in the repository and report the properties lab 3 grades.

Lab 3 is marked on the **shape of a pipeline split across files**, so reading one
file at a time is not enough. A job whose body is

    uses: ./.github/workflows/_build-and-test.yml

has that file's jobs as its body, and the gate the `qa` section looks for may sit
inside the caller, inside a called workflow, or across the boundary between them.

Resolution is **one level deep**, which is the shape the lab asks for and close
enough to GitHub's own nesting limit to be worth no more.

Output is one `KEY value` line per fact, read by the section scripts with grep.
"""
import glob
import os
import re
import sys

import yaml

WFDIR = sys.argv[1] if len(sys.argv) > 1 else ".github/workflows"
ACTDIR = sys.argv[2] if len(sys.argv) > 2 else ".github/actions"

docs, texts = {}, {}
for path in sorted(glob.glob(os.path.join(WFDIR, "*.yml")) + glob.glob(os.path.join(WFDIR, "*.yaml"))):
    name = os.path.basename(path)
    texts[name] = open(path, errors="replace").read()
    try:
        docs[name] = yaml.safe_load(texts[name]) or {}
    except Exception:
        docs[name] = None

# `on:` is YAML 1.1, so safe_load gives back the boolean True as the key.
def triggers(doc):
    """`on:` is YAML 1.1, so the key comes back as the boolean True. It is also
    allowed to be a bare string or a list, which have no keys at all."""
    raw = None
    for key in ("on", True):
        if isinstance(doc, dict) and key in doc:
            raw = doc[key]
            break
    if isinstance(raw, dict):
        return raw
    if isinstance(raw, str):
        return {raw: {}}
    if isinstance(raw, list):
        return {str(k): {} for k in raw}
    return {}


def jobs_of(name):
    doc = docs.get(name)
    return (doc or {}).get("jobs") or {} if isinstance(doc, dict) else {}


def body(name, job):
    return yaml.dump(jobs_of(name).get(job, {}), default_flow_style=False)


def needs_of(name, job):
    n = (jobs_of(name).get(job) or {}).get("needs") or []
    return [n] if isinstance(n, str) else list(n)


def call_target(name, job):
    """The workflow file this job calls, or None. Local calls only resolve."""
    uses = (jobs_of(name).get(job) or {}).get("uses")
    if not isinstance(uses, str):
        return None
    ref = uses.split("@")[0]
    if ".github/workflows/" not in ref:
        return None
    return os.path.basename(ref), ref.startswith("./")


def is_called(name):
    return "workflow_call" in (triggers(docs.get(name)) or {})


CALLERS = [n for n in docs if docs.get(n) is not None and not is_called(n)]
CALLED = [n for n in docs if docs.get(n) is not None and is_called(n)]

# effective text of a node: its own body, plus the whole file it calls
def effective(name, job):
    text = body(name, job)
    target = call_target(name, job)
    if target and target[0] in texts:
        text += "\n" + texts[target[0]]
    return text


def runs_tests(t):
    return "pytest" in t


def builds(t):
    return "docker build" in t or "build-push-action" in t


def pushes(t):
    return "docker push" in t or "push: true" in t or "push: ${{" in t


def promotes(t):
    return "published.txt" in t or "imagetools create" in t or "promote" in t.lower()


def is_qa(name, job, t):
    target = call_target(name, job)
    if target and "qa" in target[0].lower():
        return True
    if "qa" in job.lower() and runs_tests(t):
        return True
    return "QA_BASE_URL" in t or "qa/" in t


# ── sites: where each thing happens, by (file, job) ──────────────────────────
PUSH_SITES, QA_SITES, TEST_SITES, BUILD_SITES, SHIP_SITES = [], [], [], [], []
for name in docs:
    for job in jobs_of(name):
        # the job's id counts as part of it: a job called `promote` whose only
        # step writes a summary line is still the promotion
        own = body(name, job) + "\n# job: " + job
        qa_here = is_qa(name, job, own)
        if pushes(own):
            PUSH_SITES.append((name, job))
        if qa_here:
            QA_SITES.append((name, job))
        # the unit suite, which is not the qa suite: both run pytest
        if runs_tests(own) and not qa_here:
            TEST_SITES.append((name, job))
        if builds(own):
            BUILD_SITES.append((name, job))
        if pushes(own) or promotes(own):
            SHIP_SITES.append((name, job))


def reaches(name, frm, to, seen=frozenset()):
    for n in needs_of(name, frm):
        if n == to:
            return True
        if n not in seen and reaches(name, n, to, seen | {n}):
            return True
    return False


def lift(site):
    """The caller-level nodes that stand for this site."""
    name, job = site
    if name in CALLERS:
        return [(name, job)]
    out = []
    for caller in CALLERS:
        for cj in jobs_of(caller):
            target = call_target(caller, cj)
            if target and target[0] == name:
                out.append((caller, cj))
    return out


def gated(push_site, gate_sites):
    for gate in gate_sites:
        # one job, two steps: the second never runs if the first goes red
        if push_site == gate:
            return True
        if push_site[0] == gate[0] and reaches(push_site[0], push_site[1], gate[1]):
            return True
        for pf, pj in lift(push_site):
            for gf, gj in lift(gate):
                if pf == gf and pj != gj and reaches(pf, pj, gj):
                    return True
    return False


out = []
out.append(f"WORKFLOWS {len(docs)}")
for name in docs:
    if docs[name] is None:
        out.append(f"UNPARSEABLE {name}")
for name in CALLED:
    out.append(f"CALLED {name}")

local_calls = 0
for caller in CALLERS:
    for job in jobs_of(caller):
        target = call_target(caller, job)
        if target:
            out.append(f"CALLER {caller}:{job} -> {target[0]} {'local' if target[1] else 'remote'}")
            local_calls += int(bool(target[1]))
out.append(f"LOCALCALLS {local_calls}")

# typed inputs, and whether the called workflow reads any of them
typed, untyped, inputs_total = 0, 0, 0
for name in CALLED:
    spec = (triggers(docs[name]).get("workflow_call") or {}) or {}
    for key, val in (spec.get("inputs") or {}).items():
        inputs_total += 1
        if isinstance(val, dict) and val.get("type"):
            typed += 1
        else:
            untyped += 1
out.append(f"INPUTS {inputs_total} typed {typed} untyped {untyped}")
out.append("INPUTUSED " + ("yes" if any("inputs." in texts[n] for n in CALLED) else "no"))

wf_outputs = [n for n in CALLED if (triggers(docs[n]).get("workflow_call") or {}).get("outputs")]
out.append("WFOUTPUTS " + (",".join(wf_outputs) if wf_outputs else "-"))
consumed = any(".outputs." in texts[n] and "needs." in texts[n] for n in CALLERS)
out.append("OUTPUTCONSUMED " + ("yes" if consumed else "no"))

# secrets: declared on the called side, or inherited at the call site
secrets = any((triggers(docs[n]).get("workflow_call") or {}).get("secrets") for n in CALLED) \
    or any("secrets: inherit" in texts[n] for n in CALLERS)
out.append("SECRETS " + ("yes" if secrets else "no"))

# the composite action, and whether the reusable workflow is what calls it
composite = "-"
for path in sorted(glob.glob(os.path.join(ACTDIR, "*", "action.yml")) + glob.glob(os.path.join(ACTDIR, "*", "action.yaml"))):
    if "using: composite" in open(path, errors="replace").read().replace('"', "").replace("'", ""):
        composite = path
        break
out.append(f"COMPOSITE {composite}")
out.append("COMPOSITEINREUSE " + ("yes" if any("/.github/actions/" in texts[n] for n in CALLED) else "no"))

# one definition, not four copies
out.append(f"TESTFILES {len({n for n, _ in TEST_SITES})}")
out.append(f"BUILDFILES {len({n for n, _ in BUILD_SITES})}")

for name, job in TEST_SITES:
    out.append(f"TESTS {name}:{job}")
for name, job in BUILD_SITES:
    out.append(f"BUILDS {name}:{job}")
for name, job in PUSH_SITES:
    out.append(f"PUSHES {name}:{job}")
for name, job in QA_SITES:
    out.append(f"QA {name}:{job}")

# Shipping must depend on QA. A qa job nothing depends on is decoration: a red
# suite would change nothing about what reaches the registry.
shipped = [s for s in SHIP_SITES if s not in QA_SITES]
out.append("GATE " + ("yes" if shipped and QA_SITES and any(gated(s, QA_SITES) for s in shipped) else "no"))
out.append("GATEALL " + ("yes" if shipped and QA_SITES and all(gated(s, QA_SITES) for s in shipped) else "no"))
out.append("TESTGATE " + ("yes" if PUSH_SITES and TEST_SITES and all(gated(p, TEST_SITES) for p in PUSH_SITES) else "no"))
for name, job in SHIP_SITES:
    out.append(f"SHIPS {name}:{job}")

# the qa call: does it RECEIVE the image, or does it know it already?
qa_input, qa_needs = "no", "no"
for name, job in QA_SITES:
    for cf, cj in lift((name, job)):
        spec = jobs_of(cf).get(cj) or {}
        with_ = spec.get("with") or {}
        if any("${{" in str(v) for v in with_.values()):
            qa_input = "yes"
        if needs_of(cf, cj):
            qa_needs = "yes"
out.append(f"QAINPUT {qa_input}")
out.append(f"QANEEDS {qa_needs}")

def qa_chain():
    """The qa node, its call site, and whatever job the call site reads an output
    from — because the digest is produced there, not inside the qa workflow."""
    text = ""
    for name, job in QA_SITES:
        text += effective(name, job)
        for cf, cj in lift((name, job)):
            site = body(cf, cj)
            text += site
            for upstream in re.findall(r"needs\.([A-Za-z0-9_-]+)\.outputs", site):
                text += effective(cf, upstream)
    return text


qa_text = qa_chain()
out.append("QADIGEST " + ("yes" if ("sha256:" in qa_text or "digest" in qa_text.lower()) else "no"))
out.append("QALATEST " + ("yes" if ":latest" in qa_text else "no"))
out.append("QASUMMARY " + ("yes" if "GITHUB_STEP_SUMMARY" in qa_text else "no"))

# third-party actions, and what they are pinned to
for name in docs:
    for line in texts.get(name, "").splitlines():
        s = line.strip()
        if not s.startswith("- uses:") and not s.startswith("uses:"):
            continue
        ref = s.split("uses:", 1)[1].strip().strip('"').strip("'")
        if ref.startswith("./") or ".github/workflows/" in ref:
            continue
        if "@" not in ref:
            out.append(f"UNPINNED {name} {ref} (no ref at all)")
        else:
            tag = ref.split("@")[1]
            if tag in ("main", "master", "develop", "latest", "HEAD"):
                out.append(f"UNPINNED {name} {ref} ({tag} is a branch)")

# concurrency, per workflow and per job
for name in docs:
    doc = docs[name] or {}
    conc = doc.get("concurrency")
    if conc is not None:
        group = conc.get("group", conc) if isinstance(conc, dict) else conc
        cancel = str(conc.get("cancel-in-progress", False)) if isinstance(conc, dict) else "False"
        out.append(f"CONC {name} workflow cancel={cancel} group={group}")
    for job in jobs_of(name):
        jc = (jobs_of(name).get(job) or {}).get("concurrency")
        if jc is not None:
            group = jc.get("group", jc) if isinstance(jc, dict) else jc
            cancel = str(jc.get("cancel-in-progress", False)) if isinstance(jc, dict) else "False"
            out.append(f"CONC {name} {job} cancel={cancel} group={group}")
    paths = (triggers(doc).get("push") or {})
    if isinstance(paths, dict) and paths.get("paths"):
        out.append(f"PATHS {name} {','.join(paths['paths'])}")

print("\n".join(out))
