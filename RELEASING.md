# Releasing

This is the maintainer's document. Contributors don't need it —
see `CONTRIBUTING.md`.

## Versioning policy

**All four packages share one version number and are released together
(lockstep).** `kumi`, `kumi_admin`, `kumi_storage` and `kumi_new` are
always tagged and published at the same version.

Why lockstep, given they're independent mix projects:

- `kumi_admin` and `kumi_storage` depend on `kumi`, and during
  development they do it by path. At publish time each path dependency
  becomes a version dependency. If versions moved independently, every
  release would need a compatibility matrix; with lockstep, the
  requirement is mechanical — `{:kumi, "~> X.Y"}`.
- A user's mental model is "I'm on Kumi 0.6", not "kumi 0.6.1 with
  kumi_admin 0.4.2".

The cost is honest and accepted: a package with no changes still gets a
version bump. If versions ever genuinely need to diverge, switch to
per-package tags (`kumi/vX.Y.Z`) at that point — don't pre-build for it.

Semantic versioning, with the pre-1.0 caveat that **while the major
version is 0, a minor bump may break API**. Specifically:

| Change | Bump |
|---|---|
| Removing or renaming a DSL option, mix task flag, or public function | minor (pre-1.0) / major (post-1.0) |
| A schema change classified differently by `Kumi.Plan.Safety` | minor — it changes what `--check` exits with |
| New DSL option, new mix task, new admin capability | minor |
| Bug fix, docs, internal refactor with no observable change | patch |

Reclassifying an operation from SAFE to DANGEROUS is *not* a breaking
change to be avoided — failing closed is the contract. Reclassifying the
other direction is, and needs a very good reason.

## Tagging

One annotated tag per release, on `main`, named `vX.Y.Z`:

```bash
# 1. Bump the version in all four mix.exs files to the same number.
#    Also bump the `{:kumi, "~> X.Y"}` requirement in kumi_admin and
#    kumi_storage if the minor changed.

# 2. Move the Unreleased section of CHANGELOG.md into a
#    ## [X.Y.Z] - YYYY-MM-DD section and leave a fresh empty Unreleased.

# 3. Verify every package from a clean state.
for p in kumi kumi_admin kumi_new kumi_storage; do
  (cd $p && mix deps.get && mix compile --warnings-as-errors \
     && mix format --check-formatted && mix test) || echo "FAILED: $p"
done

# 4. Commit, tag, push.
git commit -am "chore: release vX.Y.Z"
git tag -a vX.Y.Z -m "vX.Y.Z"
git push origin main --follow-tags
```

Wait for CI to be green on the tagged commit before publishing anything.

Never move or delete a published tag. A mistake gets a new patch
release, not a re-tag.

## Publishing to Hex

Not yet possible — see the checklist below. Once a license is chosen,
each package needs a `package/0` in its `mix.exs` (description, licenses,
links, `files`) and `:ex_doc` as a dev dependency. Deliberately not
stubbed out now: incomplete Hex metadata makes `mix hex.build` fail in a
confusing way, and a wrong license in a published package is very hard to
walk back.

Publish order matters, because the dependents require the core from Hex:
`kumi` → then `kumi_admin` and `kumi_storage` → `kumi_new` last (it has
no dependencies, but its templates reference the published versions).

`kumi_new` is also an archive: after publishing, verify
`mix archive.install hex kumi_new` works from a directory outside this
repository.

## Before the repository goes public

These are decisions, not tasks — they need a human, and several block
each other.

- [ ] **Project name.** "Kumi" is the working name and appears in module
      names, mix task names, package names, the generated app's chrome,
      and every guide. Changing it later is a mechanical but wide rename,
      and it becomes irreversible the moment the Hex package names are
      claimed. Decide before the first publish, not before the first push.
- [ ] **License.** Blocks Hex publishing entirely and determines whether
      anyone can legally use the code. Needs a `LICENSE` file at the repo
      root and a matching `licenses:` entry in each package's Hex
      metadata.
- [ ] **First version number.** Every `mix.exs` says `0.1.0` while the
      commit history talks about v0.1 through v0.5. Pick the real number
      at the first tag and make all four files agree.
- [ ] **Private documents.** The blueprint documents and the internal
      friction log are working notes, in Japanese, and are not intended
      to be published. Decide per file: delete, move out of the
      repository, or keep deliberately. Note that removing them from
      `main` does **not** remove them from history — if that matters,
      it has to happen before the repository's visibility changes.
- [ ] **`CLAUDE.md`.** Currently an internal working-instructions file.
      Either rewrite it as public contributor guidance or remove it.
- [ ] **`kumi_storage`'s public status.** It is tested by CI and
      documented here, but whether it ships in the first public release
      or stays internal is undecided.
- [ ] **Code of conduct.** Standard practice for a public repository, and
      a real one needs a real reporting contact. Adding a Contributor
      Covenant file with an unfilled contact placeholder is worse than
      not having one.
- [ ] **Design assets.** The logo and brand notes under `design/` are
      committed. Confirm they're intended to be public, and whether they
      carry the same license as the code (usually they shouldn't).

## After the repository goes public

Repository settings, not files — nothing in this repo can enforce them,
so they're listed here so they don't get forgotten:

```bash
# Require CI to pass and a review before merging to main.
# The four contexts are the CI job names, one per package.
gh api -X PUT repos/:owner/:repo/branches/main/protection \
  -H "Accept: application/vnd.github+json" \
  -f 'required_status_checks[strict]=true' \
  -f 'required_status_checks[contexts][]=kumi' \
  -f 'required_status_checks[contexts][]=kumi_admin' \
  -f 'required_status_checks[contexts][]=kumi_new' \
  -f 'required_status_checks[contexts][]=kumi_storage' \
  -f 'required_pull_request_reviews[required_approving_review_count]=1' \
  -f 'enforce_admins=false' \
  -f 'restrictions=null'
```

- [ ] Branch protection on `main` (above).
- [ ] Squash-merge only, so PR titles become the commit log —
      `CONTRIBUTING.md` tells contributors to write PR titles as
      conventional-commit lines.
- [ ] Enable **private vulnerability reporting** (Settings → Security).
      `SECURITY.md` tells reporters to use it; without it enabled that
      instruction is a dead end.
- [ ] Confirm Dependabot is running for all four configured ecosystems.
- [ ] Require workflow approval for first-time contributors (Settings →
      Actions), so a fork PR can't run CI unreviewed.
