# Regression

**2026-11-18.** A release went out with `COUNTER_FILE` pointing at a path the container could not
write, so `/visits` answered 503 for everyone while `/health` stayed green. Nothing in the unit
suite touched the filesystem the image really has.

`test_visits_counts_up` exists because of that, and it is the check the branch rule requires:
`section · qa`. It is a required check, so a release cannot go out while it is red.
