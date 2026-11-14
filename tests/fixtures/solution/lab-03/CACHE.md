# Cache

| run | what | time |
|---|---|---|
| cold | nothing cached, first run after the key changed | 4m 38s |
| warm | same commit, nothing changed | 1m 52s |

**Saved 2m 46s**, about 60%. Most of it was the dependency cache — `pip install` went from 71s to
4s — and the layer cache took the docker build from 96s to 21s.

- cold: https://github.com/student/catshop-labs/actions/runs/1111111111
- warm: https://github.com/student/catshop-labs/actions/runs/2222222222
