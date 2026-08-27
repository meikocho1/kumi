<!--
Thanks for contributing. CI runs format / compile --warnings-as-errors /
test for all four packages on every PR; a red run is the first thing a
reviewer will look at, so it's worth running the same commands locally
first (see CONTRIBUTING.md).
-->

## What this changes

<!-- One or two sentences. What behaviour is different after this PR? -->

## Why

<!--
The problem, not the patch. If there's an issue, link it: Closes #123.
If this changes a decision recorded in a guide or README, say so — Kumi
has a few deliberate design constraints, and a PR that crosses one needs
a discussion, not just a review.
-->

## How it was verified

<!--
A green test suite is necessary, not sufficient. If this touches
rendering, HTTP headers, generated projects, or SQL, say what you
actually ran and what you observed.
-->

- [ ] `mix format --check-formatted` and `mix compile --warnings-as-errors` are clean in every package this touches
- [ ] `mix test` passes in every package this touches
- [ ] New behaviour has a test that would fail without the change
- [ ] Documentation (`README.md`, `guides/`, moduledocs) updated if behaviour changed

## Anything reviewers should know

<!--
Deliberate cut corners, known limitations, follow-up work, or a part you
would like a second opinion on. Naming a limitation is always better
than leaving a reviewer to find it.
-->
