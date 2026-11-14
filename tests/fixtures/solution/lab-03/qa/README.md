# qa — the suite, and the harness that stands something up for it

Two of these three files are **given**. The suite is yours.

| File | | |
|---|---|---|
| `compose.qa.yaml` | given | the stack: the **pulled** image, Postgres, and the partner behind a profile |
| `run.sh` | given | pull · up · wait · drive · tear down. Exit status is the suite's |
| `test_*.py` | **yours** | the scenarios |

## Calling it from your QA workflow

```yaml
# .github/workflows/_qa.yml
on:
  workflow_call:
    inputs:
      image:
        description: the digest to test
        required: true
        type: string

jobs:
  qa:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - run: pip install -r lab-03/requirements-dev.txt
      - run: bash lab-03/qa/run.sh
        env:
          QA_IMAGE: ${{ inputs.image }}
```

That is the whole call. `run.sh` prints what it is doing, writes a summary line when it is running
in Actions, and leaves `lab-03/qa-report.xml` behind for you to upload.

## The knobs

| variable | default | |
|---|---|---|
| `QA_IMAGE` | — | **required.** The image to test, as a **digest** |
| `QA_PORT` | `8080` | the host port the stack is published on |
| `QA_BASE_URL` | `http://localhost:$QA_PORT` | what your suite is pointed at — **read it from the environment** |
| `QA_PROFILE` | unset | `partner` also starts the stubbed partner |
| `QA_REPORT` | `lab-03/qa-report.xml` | junit output |
| `QA_PYTHON` | `python3` | the interpreter that has `pytest` and `requests` |
| `QA_KEEP` | unset | `1` leaves the stack up so you can poke it |

## Two things in here are the lesson

**The app service has no `build:`.** It cannot have one. Every compose file you have written so far
built an image; this one pulls a digest, because an AQA run tests what was published, not what this
machine can make. If the digest is wrong, nothing starts — which is the correct failure.

**The partner is behind a profile, so by default it is absent** and `/price` answers `502`. A
dependency that is not there is a case worth having, and it is the one your unit tests cannot see.
`QA_PROFILE` reaches your suite as an environment variable, so one case can assert both outcomes
and the stack decides which one applies — which is exactly the move lab 5 makes with three
environments. Run it both ways:

```bash
QA_IMAGE=ghcr.io/you/catshop@sha256:... bash lab-03/qa/run.sh
QA_IMAGE=ghcr.io/you/catshop@sha256:... QA_PROFILE=partner bash lab-03/qa/run.sh
```

Locally, point your suite at anything that answers — a container you started by hand, or the app
running from your terminal:

```bash
QA_BASE_URL=http://localhost:8080 python3 -m pytest lab-03/qa -q
```
