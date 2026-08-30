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

Every package now carries `package/0` metadata (MIT, description, links,
`files`) and builds a valid tarball — verified with `mix hex.build` in all
four. Two things about that are non-obvious:

**`KUMI_PUBLISH=1`.** `mix hex.build` refuses any non-Hex dependency, and
`kumi_admin`/`kumi_storage` depend on `kumi` by path during development.
Their `kumi_dep/0` returns `{:kumi, path: "../kumi"}` normally and
`{:kumi, "~> 0.1"}` when `KUMI_PUBLISH` is set. Every publish command for
those two packages must set it:

```bash
(cd kumi        && mix hex.publish)
(cd kumi_admin  && KUMI_PUBLISH=1 mix hex.publish)
(cd kumi_storage && KUMI_PUBLISH=1 mix hex.publish)
(cd kumi_new    && mix hex.publish package)   # package only — see below
```

**`kumi_new` publishes without docs.** It has no dependencies at all, not
even `:ex_doc`, because `mix archive.build` compiles in `:dev` — a single
unfetched dev dependency would break `mix archive.install` for anyone who
had not run `mix deps.get` in that directory first. Keeping the package
dependency-free is worth more than its hexdocs page, so publish it with
`mix hex.publish package`.

Package names on Hex were unclaimed when this was written; claiming them
is the irreversible step.

Publish order matters, because the dependents require the core from Hex:
`kumi` → then `kumi_admin` and `kumi_storage` → `kumi_new` last (it has
no dependencies, but its templates reference the published versions).

`kumi_new` is also an archive: after publishing, verify
`mix archive.install hex kumi_new` works from a directory outside this
repository.

## Before the repository goes public

These are decisions, not tasks — they need a human, and several block
each other.

Settled on 2026-08-30, with what was done for each:

- [x] **Project name — "Kumi", final.** All four Hex names
      (`kumi`, `kumi_admin`, `kumi_new`, `kumi_storage`) were unclaimed
      when checked. Nothing was renamed.
- [x] **License — MIT.** `LICENSE` at the repo root and a copy in each
      package (Hex packages cannot include files above their own root).
      `licenses: ["MIT"]` in all four `package/0`. The copyright line
      reads "Kumi contributors" — change it before the first tag if a
      named holder is wanted.
- [x] **`kumi_storage` ships in the first release.** Four packages,
      lockstep, as the versioning policy above already assumed.
- [x] **Private documents — removed from `main`, history untouched.** The
      three blueprints and the friction log are now in `.gitignore` and
      untracked; the files stay on the working copy. Earlier versions
      remain reachable in git history, which was the accepted trade.
- [x] **`CLAUDE.md`** was rewritten as public English contributor and
      agent guidance. The internal-only parts moved to a gitignored
      `CLAUDE.local.md`.

Still open:

- [ ] **First version number.** Every `mix.exs` says `0.1.0` while the
      commit history talks about v0.1 through v0.5. Pick the real number
      at the first tag and make all four files agree.
- [ ] **Code of conduct.** Standard practice for a public repository, and
      a real one needs a real reporting contact. Adding a Contributor
      Covenant file with an unfilled contact placeholder is worse than
      not having one.
- [ ] **Design assets.** The logo and brand notes under `design/` are
      committed, and the root `README.md` now embeds the logo and a
      screenshot — which assumes they're public. Confirm that, and decide
      whether they carry the same license as the code (usually they
      shouldn't).

## After the repository goes public

Repository settings, not files — nothing in this repo can enforce them,
so they're listed here so they don't get forgotten:

```bash
# Require CI to pass and a review before merging to main.
# The four contexts below are the exact names GitHub reports for the
# matrix jobs — verified with `gh pr checks <n>` on a real pull request,
# not inferred from the workflow file. A context string that doesn't
# match makes branch protection permanently unsatisfiable, silently.
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
- [ ] **Enable squash-merge and disable merge commits and rebase-merge**
      (Settings → General → Pull Requests). This is a setting, not a
      convention: `CONTRIBUTING.md` tells contributors their PR title
      becomes the commit subject, which is only true if squash is the
      only option available.
- [ ] Enable **private vulnerability reporting** (Settings → Security).
      `SECURITY.md` tells reporters to use it; without it enabled that
      instruction is a dead end.
- [ ] Confirm Dependabot is running for all four configured ecosystems.
- [ ] Require workflow approval for first-time contributors (Settings →
      Actions), so a fork PR can't run CI unreviewed.
