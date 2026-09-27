# Changelog

All notable changes to this project are documented here. The format
follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the
project follows [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

All four packages in this repository share one version number and are
released together; see `RELEASING.md`.

## [Unreleased]

Nothing has been released yet — there are no tags, and every package's
`mix.exs` still reads `0.1.0`. The entries below are what the first
release will contain, reconstructed from the commit history. On the first
tag they collapse into that version's section.

### Added

**`kumi` — the plan engine**

- `mix kumi.plan` compares the Ash resources in your code against a
  **live** Postgres database and prints a desired-vs-actual diff. This is
  a different question from the one `mix ash.codegen` answers
  (code vs. snapshot), so it sees manual database drift that codegen
  cannot. `--check` gives an exit code for scripts, `--verbose` explains
  each operation, `--app` scopes the comparison to one declared app's
  tables.
- Safety classification for every proposed operation: anything that
  deletes data is DANGEROUS, constraint tightening and rename guesses are
  REVIEW, pure additions are SAFE. Unknown type pairs fail closed. Rename
  detection runs before classification so a dropped-and-re-added column
  is recognised as a rename rather than reported as data loss.
- `--probe` (opt-in) attaches read-only row-count findings that annotate
  operations without changing their classification, so `--check` exit
  codes never depend on live data.
- Timestamp precision drift detection (a `utc_datetime` column that is
  actually `timestamp(6)` in the database, and the reverse).
- `app do locale :ja end`, and `--locale` on `mix kumi.plan` /
  `mix kumi.report`, print the prose in Japanese: safety reasons, fix
  hints, drift markers, the summary and the verdict. What stays English
  is everything a reader matches rather than reads — the operation lines
  themselves (table names, column names, Postgres types), the
  `SAFE`/`REVIEW`/`DANGEROUS` labels, the SQL inside a fix hint, and
  `--json` output, which must not change language under a script.
  Safety levels and `--check` exit codes are identical in every locale.
  The locale is *found*, not named: with no `--app`, the tasks locate the
  single `Kumi.App` in the project and read its declaration, so `locale
  :ja` stays one switch instead of becoming a flag on every invocation.
  Zero apps or several stay in English rather than guessing which one
  speaks for the repository.
  Each step's detail follows the locale too (`すべて整形済み`, `ズレなし
  — DB とアプリの定義が一致しています`), because a report printing
  `判定: ready` under `all files formatted` is half a translation. Details
  Kumi did not write — a captured compiler diagnostic, `mix test`'s own
  summary line — are printed as captured, and `--json` still emits the
  English string in every locale.
- Foreign-key delete rules are part of the comparison: `ON DELETE`
  drift between the code's `references` block and the live constraint is
  reported as its own operation, classified REVIEW in both directions
  (adding a cascade starts deleting rows; removing one makes the parent
  undeletable) and never rendered as SQL, since repairing it means DROP
  plus ADD.
- `mix kumi.apply` repairs SAFE drift in development. Four independent
  gates: the operation must be classified SAFE, must have an allowlisted
  shape (a nullable `add_column`, a non-unique `add_index`, or a
  `change_column` that only drops NOT NULL), must render to exact SQL,
  and must be complete — no default, precision, type modifier
  (`numeric(10,2)`, `vector(1536)`) or index option (`where`, `using`,
  `include`) silently dropped. It runs in one transaction, re-introspects
  afterwards to verify the result, refuses to run outside `MIX_ENV=dev`,
  and refuses to run while a migration is pending or
  `mix ash.codegen --check` fails.
- Fix hints: each diff operation carries a remediation line, favouring
  "add it to your code" over "drop it from the database".
- `Kumi.App`, a Spark DSL for application-level intent — title,
  the list of resources, admin navigation, dashboard metrics
  (`count`/`sum`), and workflow stages. It deliberately does not
  duplicate Ash's own domain DSL. Compile-time verifiers reject
  non-Ash resources, navigation entries outside the declared resource
  list, metrics over missing or non-public fields, and workflow stages
  outside an attribute's `one_of` constraint.
- `Kumi.Resource`, a shorthand that expands to a standard Ash resource,
  plus `mix kumi.expand` to print exactly what it compiles to. A test
  asserts the printed source and the compiled definition agree.
  `fields do ... end` also takes `identity name, [attributes]`, spelled
  exactly as Ash spells it, for the unique constraints that nearly every
  real resource has — without it, a second table was usually enough to
  force a drop to plain Ash. Identity *options* (`nils_distinct?`,
  `where`, `eager_check?`, `pre_check?`) stay escape-hatch territory and
  are rejected with a message pointing at `mix kumi.expand`.
  `belongs_to` takes `required: true` and `on_delete:` (`:delete` /
  `:nilify` / `:nothing` / `:restrict`, validated at compile time),
  expanding to an AshPostgres `references` entry. Before this, a
  shorthand foreign key had no `ON DELETE` rule and no way to be
  mandatory: the parent row could not be deleted once anything referenced
  it, and nothing failed until someone tried.
- `mix kumi.report`, a validation harness that runs format, compile,
  test, `ash.codegen --check` and the plan, then emits a single verdict
  (human-readable or `--json`).
- `mix kumi.describe`, the read-only counterpart to that harness: it
  prints the app-level model — resources and their tables, navigation,
  workflows, dashboards, detected plugins, plan state — as JSON with a
  `schema_version`, so an agent or a CI check can read what an
  application *is* before touching its source, and a human can diff two
  of them instead of reading the diff of the code. `--no-plan` needs no
  database. It stays an index, not a second source of truth:
  `mix kumi.expand` remains the authority on what a resource compiles to.
- `mix kumi.install`, an Igniter installer that generates the app module
  and a `Core` domain and registers it.
- A guide to the Ash/Spark/AshPostgres/Igniter behaviours that cost real
  debugging time while building all of the above (`kumi/guides/`).

**`kumi_admin` — the admin**

- The admin speaks the app's language. `app do locale :ja end` switches
  every string kumi_admin ships, and `admin do labels %{...} end` names
  your own things — resources, attributes, relationships, workflows,
  stages, metrics — in free-form text in any language, checked at compile
  time against what the app actually declares. Whole phrases, not
  assembled fragments, so a label lands where each language's grammar
  wants it. An app declaring neither renders exactly as before. A host
  that wants different wording in the same language passes `strings:` to
  the router. See `kumi/guides/i18n.md`.

- The dashboard is a grid of stat cards: each metric is a small label
  over a large number, sized to scan rather than to read. It used to be a
  bulleted `name: value` list inside one narrow card — the only screen in
  the admin that had not been designed. Workflow stage counts render
  through the same component, because on this page a stage and a metric
  are the same thing: a name and a number. A policy-forbidden read still
  shows every declared metric and stage with `—` as its value.

- A LiveView admin whose sidebar, tables, forms, search and dashboard are
  derived from the App DSL, with no per-resource host code.
- Index, detail, new, edit and delete for every declared resource, with
  `belongs_to` selects, `has_many` child tables one level deep, and
  cross-field search.
- New/Edit/Delete buttons gated by `Ash.can?`. Policy-forbidden reads
  render an honest empty state instead of crashing.
- No authentication of its own: the router macro takes the host
  application's `on_mount` hooks and actor function, so the admin sits
  behind whatever the host already uses. First-run onboarding redirects to
  registration when the configured user resource has no rows yet.
- Dashboard metrics and workflow stage counts computed from real data,
  degrading to a "no access" state per widget rather than failing the
  page.
- Components organised as atoms / molecules / organisms, with a
  token-based default theme.
- Upload rendering driven purely by a marker contract, so the admin gains
  no dependency on the storage package.

**`kumi_storage` — uploads**

- `mix kumi_storage.install` generates a plain Ash `Attachment` resource
  with an `:upload` action, configures a local backend, and mounts a plug
  that serves stored files by generated key.
- A backend behaviour so other storage targets can be added, with size
  and content-type validation and path-traversal rejection in the local
  implementation.
- `:image` fields in the shorthand DSL expand to a relationship to the
  generated resource.

**`kumi` — sign-in providers**

- `mix kumi.gen.auth google|github|oidc` generates an OAuth2 sign-in
  strategy on your user resource. `mix ash_authentication.add_strategy`
  covers `password`, `magic_link` and `api_key`; the OAuth2 providers are
  hand-written DSL upstream, and this writes those same pieces as ordinary
  Ash source — the `UserIdentity` resource, the strategy block, a
  `register_with_<provider>` upsert action, and `secret_for/4` clauses
  that read credentials from application env.
- Two parts of the generated action are detected from your resource rather
  than assumed: without a unique identity it generates a plain create
  instead of DSL that will not compile, and `confirmed_at` is only set
  when that attribute exists.
- The provider console's redirect URI, the config values, and making
  `hashed_password` nullable are printed as instructions, never guessed
  at — no credential is written into source.

**`kumi_new` — the generator**

- `mix kumi.new my_app` goes from nothing to a running application in one
  command: project generation, dependency resolution, installers,
  database setup, and a themed starting page.
- Module selection at generation time, so you choose which optional
  modules (for example storage) the new project starts with.
- `--auth-strategy` selects the new project's sign-in methods, mixing the
  two generators freely: `password`, `magic_link`, `api_key` go to
  `ash_authentication`'s installer, `google` and `github` to
  `mix kumi.gen.auth` once the user resource exists. Values neither tool
  can generate are rejected before generation starts rather than failing
  part-way through.
- The generated sign-in page styles OAuth provider buttons to match the
  rest of the page, so adding Google or GitHub by hand does not leave an
  off-brand button behind.
- No runtime dependencies, so it stays installable as a Mix archive.

**Packaging**

- MIT licensed. `LICENSE` at the repository root and in each package.
- All four packages carry Hex metadata and produce a valid tarball
  (`mix hex.build`). `kumi_admin` and `kumi_storage` swap their path
  dependency on `kumi` for a version requirement when `KUMI_PUBLISH` is
  set; `kumi_new` stays dependency-free so it remains installable as a
  Mix archive.

### Changed

- `KumiStorage.Plug` requires `config: {module, function}` and no longer
  reads Application config itself (only mix tasks and host code do).
  `mix kumi_storage.install` generates
  `<App>.Core.Attachment.__kumi_storage_config__/0` and
  `forward "/uploads", KumiStorage.Plug, config: {<App>.Core.Attachment,
  :__kumi_storage_config__}`. An Attachment generated earlier keeps its
  old inline change bodies, because the installer never overwrites it:
  replace its `:upload`/`:destroy` actions with the current generated
  ones, add `__kumi_storage_config__/0`, and add `config:` to the router
  forward (the plug raises at compile time without it).
- The generated `:upload` action measures the size from the bytes; the
  declared `byte_size` argument is now optional and ignored.
- `use Kumi.Resource` accepts exactly `domain:`, `repo:` and `table:`. An
  unknown option (`extensions:`, a typo like `tabel:`), a repeated one or
  a missing one raises a readable `ArgumentError` instead of being
  dropped silently or failing with a bare `KeyError`.
- `kumi_admin/2` validates its options when the router compiles: an
  unknown key, or an `:actor` that is not a `{Module, :function}` pair,
  raises `ArgumentError`.

### Security

- The admin's LiveView session no longer carries a copy of the cookie
  session. Values such as ash_authentication's `user_token` and the CSRF
  token were signed — not encrypted — into the page's `data-phx-session`
  token, readable by any script on the page. `on_mount` hooks still see
  the cookie session through LiveView's own merge, which needs the
  endpoint's `socket "/live", Phoenix.LiveView.Socket, websocket:
  [connect_info: [session: @session_options]]` (phx.new generates it).
- `mix kumi.gen.auth` register actions reject a sign-in unless the
  provider marks the email `email_verified` (google, github and oidc;
  fails closed). With the confirmation add-on they also refuse to link an
  existing account that was never confirmed. Before, an attacker who
  controlled an unverified provider account with a victim's email could
  sign in as the victim. Actions generated earlier are not rewritten;
  re-check your `register_with_<provider>` against `guides/auth.md`.
  `mix kumi.gen.auth oidc` notes that providers which don't send
  `email_verified` by default (e.g. Microsoft Entra ID) sign no one in
  until they do.
- The generated `:upload` action stored the file while the changeset was
  being built — before authorization, and on every form validate — and
  trusted the caller's declared `byte_size`, so the size cap could be
  bypassed. It now stores only when the action runs, measures the real
  size, deletes the file when the create fails afterwards, and turns a
  malformed `:source` into a changeset error instead of a crash. The
  generated destroy deletes the file after the transaction commits and
  logs a failed delete instead of discarding it.
  `KumiStorage.Backend.Local` removes a partially written file.
- Served uploads are public to anyone holding the URL, which is now
  stated in the README, `SECURITY.md` and the installer notice; the
  generated `storage_key` is `public? false`, and the installer adds
  `/priv/uploads/` to `.gitignore`.
- The admin no longer uses a `sensitive?` or private `:name` as a
  record's label, and its create/edit form forwards only the fields it
  renders: a sensitive attribute or an upload foreign key posted by a
  client is dropped before it reaches the action.
- `mix kumi_admin.install` and `mix kumi.new` warn that every account the
  host's auth accepts is a full admin (shorthand resources carry no
  policies), and show how to restrict it. `guides/auth.md` no longer
  suggests the Google `hd` authorize parameter restricts who can sign in.

### Fixed

Bugs found and fixed during development, listed because each one is a
trap worth knowing about:

- `mix kumi.plan`, `kumi.apply`, `kumi.report` and `kumi.describe`
  crashed on a map, list or `{m, f, a}` attribute default (for example
  `default %{}`). Float, binary/term and microsecond `time` columns
  showed a permanent DANGEROUS type change on a freshly migrated
  database. Quoted SQL defaults such as `'it''s'::text` and
  `'a'::character varying` were misread.
- `mix kumi.apply` could create a different column or index than
  `mix ash.codegen` does — `numeric` for `numeric(10,2)`, a plain btree
  for a partial or GIN index — and then report the repair as verified.
  Such operations are now skipped (see the gates above).
- A shorthand module that also declared `code_interface`, `validations`,
  `changes`, `preparations`, postgres `references`, `custom_indexes`,
  `check_constraints` or `custom_statements` next to `fields do ... end`,
  or overrode the postgres `table`/`repo`, compiled silently while
  `mix kumi.expand` never printed those parts. It now fails to compile.
- The admin reported every failed save or delete as a permission error.
  "You don't have permission" now appears only for real policy denials; a
  delete blocked by a foreign key, and an upload rejected for size or
  type, say so. When a save fails, the attachments it had just uploaded
  are destroyed again instead of being orphaned.

- `mix kumi.plan` reported every column with a numeric or boolean default
  as permanent, unrepairable drift. Postgres returns those defaults
  unquoted (`0`, `false`), and only quoted defaults were being read as
  literals, so the desired and actual sides could never agree. This made
  `mix kumi.report` unable to reach `ready` on an application that had
  done nothing wrong.
- The admin ignored `sensitive? true`: the value was rendered on the list
  and detail pages and was searchable. Sensitive attributes are now
  dropped from every attribute list the admin derives — columns, detail
  page, search, and forms. Consequence: a *required* sensitive attribute
  cannot be filled in from the admin, so set it from the host
  application's own UI or from `iex`.
- The admin truncated any string column whose *name* ended in `_id` to 8
  characters, on the assumption it was a UUID foreign key. Ordinary
  business columns (`external_id`, `stripe_customer_id`) were unreadable.
  Truncation now applies only to attributes that actually back a
  `belongs_to`.
- `mix kumi.plan` crashed outright on parameterized column types such as
  pgvector's `vector(1536)`, instead of failing closed. Unmapped type
  shapes now surface as an unrecognised change and are classified
  DANGEROUS.
- The admin shipped its stylesheet as literal, uninterpolated text
  because HEEx disables `{...}` interpolation inside `<style>` — every
  test passed and the page rendered completely unstyled.
- Foreign-key columns rendered as full untruncated UUIDs, and child
  tables on a detail page included the foreign key pointing back at the
  record you were already looking at.
