#### Correctness

Is the logic correct? Are boundary conditions handled — empty lists, `nil`,
a single element, an unknown atom?

Does every `case`/`with` handle the error branch, or does an unmatched
clause raise a `CaseClauseError`/`FunctionClauseError` at runtime? A
catch-all that crashes on unexpected input is a bug **unless failing loudly
is the documented intent**; silently returning a wrong-shaped value is
always worse.

For any function that maps external or library-provided data into an
internal representation: what happens on a shape the author did not
anticipate? Prefer a fallback that produces a value which cannot be
mistaken for a valid one over a clause that raises and takes the whole
command down. (Real defect in this codebase: a type-mapping function
guarded with `when is_atom(atom)` raised `FunctionClauseError` on the
`{:vector, 1536}` tuple that AshPostgres returns for parameterized types,
making the entire schema-plan command unusable instead of reporting an
unknown type.)

Is data treated as immutable? Flag any code that mutates a struct or map
in place instead of returning a new one.

#### Ash resources, queries and policies

- **`Ash.Query.filter/2` is a macro.** It cannot take a runtime list of
  field names — `^field_atom` pins a *value*, not a field reference. Any
  dynamic, user-input-driven filter must use `Ash.Query.filter_input/2`.
- **`filter_input/2` only sees `public? true` attributes and
  relationships.** Code (or a compile-time verifier) that decides "is this
  field filterable/searchable" must check `public?` explicitly, not merely
  that the attribute exists.
- **Policy `access_type` defaults to `:filter`.** An unauthorized *read*
  returns `{:ok, []}`, not an error, while create/update/destroy raise
  `Ash.Error.Forbidden`. Any code or test that treats an empty list as
  "no data yet" can therefore hide a policy hole. Flag it.
- **`Ash.can?/3` can return `:maybe`, which is treated as `true`.** Gating
  a UI control on it is a cheap first filter, never a guarantee — the
  submit path must still handle rejection.
- **`Ash.sum/3` returns `{:ok, nil}` on an empty result set**, not
  `{:ok, 0}`. Unnormalized, it renders as a blank instead of a zero.
- **Pagination is opt-in per read action.** `Ash.read(resource, page: ...)`
  raises `PaginationRequired` unless the action declares `pagination`.
- **A `belongs_to`'s foreign key is an ordinary attribute.** Nothing marks
  it as a reference; generic form/table code must cross-reference
  `Ash.Resource.Info.public_relationships/1` on `source_attribute`.
- Does a policy-forbidden read degrade honestly (an empty state for that
  one section), or does it fail the whole page? Loading several
  relationships in a single `load:` means one forbidden child resource
  flips everything to an error.
- **N+1:** does this issue one query per row, per stage, or per
  relationship inside a loop? If a deliberate N-query loop is acceptable,
  it must say so and name the ceiling.

#### Spark DSL and macros

- In a `use`-style macro wrapping Ash, `use Ash.Resource` must expand at
  its normal position inside `__using__`. Deferring it to `@before_compile`
  compiles in isolation but breaks cross-module Spark verification under
  `--warnings-as-errors`.
- `Spark.implements_behaviour?(mod, Ash.Resource)` is always `false` for
  real resources. Resource detection must use
  `Ash.Resource.Info.resource?/1`.
- A Spark entity macro has arity `len(args) + 1`. A DSL call written with a
  trailing `do` block is one arity higher than the flat keyword form and
  will not compile against an entity that only declares positional args.
- Does a new DSL option have a compile-time verifier? An option that can
  only fail at runtime, when it could have been rejected at compile time,
  is a missed opportunity — and for anything referencing a field or
  resource, verification is the point.

#### Phoenix and LiveView

- **HEEx disables `{...}` interpolation inside `<style>` and `<script>`.**
  A component embedding `<style>{css()}</style>` compiles cleanly, passes
  every test, and ships the literal text `{css()}` to the browser. The
  correct form is `<%= Phoenix.HTML.raw(css()) %>`. This shipped in this
  codebase and rendered the entire admin unstyled.
- **Security headers:** `put_secure_browser_headers/2` on Phoenix 1.8 does
  **not** send `x-frame-options`; framing is controlled by the
  `content-security-policy` `frame-ancestors` directive. Code that makes a
  route embeddable by deleting `x-frame-options` alone is a no-op. When
  overriding that header, preserve its unrelated directives (`base-uri`)
  rather than deleting the header wholesale.
- Is a public/no-actor route deliberately outside the authenticated
  `live_session`, and is the write path it needs narrowed by the *action's
  accepted fields* rather than only by a policy? An action that accepts a
  role or ownership field an anonymous caller can set is a hole even
  behind a correct-looking policy.
- `Decimal` does not implement `Phoenix.HTML.Safe` — it cannot be
  interpolated directly into a template.

#### Security

- Is user input validated at the boundary, before it reaches a query or a
  changeset? Are query parameters and IDs treated as untrusted?
- Is any code path constructing SQL, a file path, or a redirect target
  from unvalidated input? For file paths specifically: is traversal
  (`..`) rejected, and is the served root constrained?
- Does an error message or log line leak internals — a full query, a
  stack trace, a credential, or personal data?
- Are there hardcoded secrets, tokens, hostnames, or credentials? They
  belong in configuration or the environment.
- For anything that classifies an operation as safe or dangerous: does it
  **fail closed**? An unrecognised input must take the restrictive branch.
  Failing open here is a security defect, not a bug.

#### Project architecture constraints

This repository has settled constraints. Violating one is a review
blocker, not a style note:

- **Library code takes explicit arguments; only mix tasks read
  `Application` config.** A library function that reaches into
  `Application.get_env/2` is misplaced.
- **The core package has no Phoenix dependency**, the admin package has no
  dependency on any module package (it integrates through exported marker
  functions), and the project-generator package has **no runtime
  dependencies at all** (it must stay installable as a mix archive). A new
  `deps` entry that crosses one of these is a blocker.
- **Schema-plan invariants:** rename detection runs *before* safety
  classification, and classification must stay deterministic from the
  schema alone — live-data probes may annotate a finding but must never
  change its classification, or scripted exit codes become
  data-dependent.
- **Never suppress a real schema diff to make a test pass.** The
  "clean checkout produces an empty plan" assertions are the project's
  core regression gate.
- **No backward-compatibility shims.** A deprecated path is deleted, not
  kept behind a fallback.

#### Maintainability

Do names express intent? Is the function small enough to hold in your
head, and is nesting shallow?

Is there duplicated logic that should have one home — particularly two
places deriving the same thing (a SQL string, a column list, a label) that
can silently drift apart?

Does a deliberate simplification with a real ceiling (a global lock, an
O(n²) scan, a naive heuristic, a missing exact count) say so in a comment
naming the ceiling? An unmarked corner is indistinguishable from an
oversight.

Do comments explain *why*, especially where upstream behaviour is
surprising? A comment restating the code adds nothing; a comment recording
why an obvious-looking alternative does not work is the most valuable line
in the file.

#### Test coverage

Does the new behaviour have a test that would **fail if the
implementation were deleted**? Specifically flag:

- an assertion on the *absence* of something that nothing in the stack
  ever produces (this passed for months in this codebase while the
  feature it guarded was completely broken);
- an assertion loose enough to match unrelated output (`html =~ "new"`
  matching a button's href);
- a test asserting a hardcoded return value.

Are boundary conditions covered — empty, `nil`, forbidden, unknown input?

If the change affects rendered HTML, HTTP headers, generated projects, or
SQL, a green test suite is not sufficient evidence. Is there any sign the
author verified it the way a user meets it?
