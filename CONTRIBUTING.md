# Contributing to Kumi

Thanks for taking the time. This document is the whole process — there is
no separate wiki, and nothing here assumes you have talked to a
maintainer first.

## Table of contents

- [What kind of contribution fits](#what-kind-of-contribution-fits)
- [Repository layout](#repository-layout)
- [Setting up](#setting-up)
- [Running the checks](#running-the-checks)
- [Making a change](#making-a-change)
- [Commit messages](#commit-messages)
- [Opening a pull request](#opening-a-pull-request)
- [What a reviewer will look for](#what-a-reviewer-will-look-for)
- [Reporting bugs and proposing features](#reporting-bugs-and-proposing-features)

## What kind of contribution fits

Kumi has a small number of design constraints that are settled, and
knowing them saves you writing a PR that can't be merged as-is:

1. **Real Ash, always visible.** The Kumi DSLs compile to ordinary,
   inspectable Ash resources. `mix kumi.expand` must always print exactly
   what a shorthand resource compiles to, and dropping down to
   hand-written Ash is a supported, first-class escape hatch — never a
   fallback for when Kumi breaks. A feature that can only work by hiding
   Ash or by generating something `kumi.expand` can't print doesn't fit.
2. **Ash/AshPostgres is the only compile target.** There is no Ecto
   adapter and no persistence abstraction layer. Please don't add one.
3. **Schema diffing complements `mix ash.codegen`, it doesn't replace
   it.** `mix kumi.plan` compares your code against a *live* database,
   which is a different question from the code-vs-snapshot question
   `ash.codegen` answers. Both are meant to be used.
4. **`kumi_new` has no runtime dependencies** and must stay installable
   as a mix archive. Adding a dependency to it breaks that.

Everything else is open: bug fixes, new admin capabilities, new modules,
docs, guides, better error messages. If you want to change one of the
four constraints above, open an issue describing the problem first — the
discussion is worth having, but it should happen before you write the
diff.

## Repository layout

This is a monorepo of four independent mix projects:

| Directory | What it is | Dependencies |
|---|---|---|
| `kumi/` | Core: schema diffing, safety classification, the App and Resource DSLs, the mix tasks | ash, ash_postgres, spark, ecto_sql, postgrex (**no Phoenix — keep it that way**) |
| `kumi_admin/` | The LiveView admin, driven by the App DSL | kumi (path), phoenix, phoenix_live_view, ash_phoenix |
| `kumi_storage/` | Uploads, as an installable module | kumi (path), ash, plug (no Phoenix) |
| `kumi_new/` | The `mix kumi.new` project generator | none, by design |

`kumi_admin` reaches `kumi_storage`'s features through a small marker
contract (a generated resource exports `__kumi_attachment__/0` and
`__kumi_attachment_url__/1`) rather than by depending on the package.
Please preserve that: the admin gaining a dependency on a module package
is the thing this indirection exists to prevent.

## Setting up

You need Elixir, Erlang/OTP, and a Postgres you can throw away.

**Toolchain.** The versions CI uses are pinned in `.tool-versions` at the
repo root; `asdf install` or `mise install` will pick them up. Any Elixir
and OTP satisfying each package's `elixir:` requirement should work — CI
is the authority on what's actually supported.

**Postgres.** Only `kumi`'s test suite needs a database, and it expects
one on `localhost:5434` with user and password `postgres`. The port is
non-standard on purpose, so a checkout never collides with a Postgres you
already run:

```bash
docker run -d --name kumi_db \
  -e POSTGRES_USER=postgres \
  -e POSTGRES_PASSWORD=postgres \
  -p 5434:5432 \
  postgres:17-alpine
```

Podman works identically (`podman run ...`). The test suite creates and
migrates its own database (`kumi_test`); you don't need to create
anything by hand.

Then, in each package you plan to touch:

```bash
cd kumi           # or kumi_admin, kumi_new, kumi_storage
mix deps.get
```

## Running the checks

CI runs exactly these three commands per package, in this order. Running
them locally first is the fastest way to a green PR:

```bash
mix compile --warnings-as-errors
mix format --check-formatted
mix test
```

Compile before checking formatting: `.formatter.exs` loads Spark's DSL
formatter plugins, which have to be compiled first.

`kumi`'s `mix test` is aliased to run `ash.setup --quiet` beforehand, so
it will create and migrate its test database on a fresh checkout without
any extra step.

To run one test:

```bash
mix test test/kumi/diff_test.exs:42
```

### If you are working inside a host application

When you're developing against a real app that uses Kumi (rather than
inside these packages), there's one extra harness worth knowing:

```bash
mix kumi.report            # format / compile / test / ash.codegen --check / kumi.plan
mix kumi.report --json     # the same, machine-readable
```

It runs the same checks CI runs, plus two host-app-specific ones, and
prints a single verdict. It is **not** part of CI for this repo (it needs
a host app with a repo and domains configured); think of it as the
pre-PR check for application code, not for library code.

One gotcha that costs everyone an hour the first time: generating
migrations for resources that live under `test/support` needs the env
set explicitly — `MIX_ENV=test mix ash.codegen NAME`. Without it the task
silently generates nothing.

## Making a change

- **Read before you write.** Kumi's plan pipeline has ordering
  invariants that aren't obvious from any single file (rename detection
  must run before safety classification, and classification must stay
  deterministic from schema alone). If you're changing that area, read
  the moduledocs in `kumi/lib/kumi/plan/` first.
- **Never suppress a real diff to make a test pass.** The zero-diff
  assertions — a clean checkout must produce an empty plan — are the core
  regression gate of the whole project. If your change makes one fail,
  the diff is telling you something true.
- **Prefer the smallest change that fixes the root cause.** A guard in
  one shared function beats the same guard in five callers.
- **Match the surrounding style,** including comment density. Comments in
  this codebase tend to explain *why*, especially where upstream
  behaviour is surprising; that's deliberate.
- **New behaviour needs a test that would fail without it.** A test that
  would still pass if you deleted the implementation isn't a test. This
  has bitten this project for real: a check asserting a response header
  was *absent* passed happily against a framework version that never sent
  that header in the first place, while the actual feature was broken.
- **A green suite is necessary, not sufficient.** If your change affects
  rendered HTML, HTTP headers, generated projects, or SQL, verify it the
  way a user meets it — load the page, curl the endpoint, generate the
  app — and say in the PR what you observed. Several bugs in this
  project's history were invisible to a fully green test suite.

## Commit messages

Conventional commits, imperative mood, English:

```
<type>: <description>

<optional body>
```

Types in use: `feat`, `fix`, `refactor`, `docs`, `test`, `chore`, `perf`,
`ci`. Scope the type to a package when it's specific to one:

```
feat(kumi_admin): gate delete buttons on Ash.can?
fix(kumi): don't crash mix kumi.plan on parameterized column types
docs: document the JSON:API include depth story
```

Small, coherent commits are easier to review than one large one, but
don't split a change and its test apart.

## Opening a pull request

1. Branch from `main`.
2. Push and open a PR. The template asks what changed, why, and how you
   verified it — the third one is the part reviewers care most about.
3. CI runs the three checks above for all four packages on every PR. It
   must be green before review; a red run is almost always faster for you
   to read than for a reviewer to relay.
4. Keep the PR focused. Unrelated cleanups in the same diff make a change
   harder to evaluate and harder to revert.
5. Rebasing to resolve conflicts is fine and welcome. Force-pushing to
   your own PR branch is fine.

Maintainers squash-merge, so your PR title becomes the commit subject —
write it as a conventional-commit line.

## What a reviewer will look for

In roughly this order:

1. Does CI pass?
2. Does the change do what the PR says, and only that?
3. Is there a test that would fail without the change?
4. Does it hold the four constraints at the top of this document?
5. Is the "how it was verified" section real — especially for anything a
   test suite can't see?
6. Are the limitations named? A PR that says "this doesn't handle X yet"
   is much easier to merge than one where the reviewer discovers X.

## Reporting bugs and proposing features

Use the issue templates — they ask for the exact commands, output, and
versions. For anything involving schema drift, the
`mix kumi.plan --verbose` output is usually the single most useful thing
you can paste.

If you think you've found a security issue, please don't open a public
issue; see `SECURITY.md`.
