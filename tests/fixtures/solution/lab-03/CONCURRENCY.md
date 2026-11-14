# Concurrency

Pushed twice, eleven seconds apart, on `lab-03`.

- cancelled: https://github.com/student/catshop-labs/actions/runs/3333333333
- the one that replaced it: https://github.com/student/catshop-labs/actions/runs/4444444444

Cancelling the first was safe because it had not reached the publish job — nothing had been pushed
to the registry yet, so there was no half-promoted digest to explain. On the `main` branch it would
not be safe: the publish job is where cancelling leaves a tag pointing at bytes QA never saw, which
is why `cancel-in-progress` is an expression and not `true`.
