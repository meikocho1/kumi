#### Does this test actually test anything?

The single most important question. A test that would still pass with the
implementation deleted is worse than no test, because it reports safety
that isn't there. Flag every one of these:

- **Vacuously true assertions.** An assertion that something is absent,
  empty, or `nil` when nothing in the stack ever produces it. Ask: what
  would have to break for this line to fail? If the answer is "nothing",
  say so. (Real case here: `assert get_resp_header(conn, "x-frame-options") == []`
  passed for months against a framework version that never sent that
  header, while the feature it guarded — cross-origin embedding — was
  broken the whole time. It would also have passed with the entire plug
  pipeline removed.)
- **Assertions loose enough to match anything.** `assert html =~ "new"`
  matches a "New" button's href on every page. Assert on a value derived
  from the fixture (an id prefix, a specific field), not on a substring
  that happens to appear.
- **Asserting a hardcoded value against a function that hardcodes it.**
- **Tests that only assert "no exception was raised"** for an operation
  whose failure mode is a wrong value or a silent empty result rather
  than a crash. Ash reads are exactly this: an unauthorized read returns
  `{:ok, []}`, so a test that only checks for the absence of an error
  proves nothing about authorization.

#### Does it test intent, not just behaviour?

Would this test still pass if the business rule changed? If yes, it is
pinned to an implementation detail rather than to the requirement. The
assertion should read as the reason the behaviour matters.

#### Coverage of the branches that matter

- The forbidden/unauthorized path, not just the happy path.
- Empty, `nil`, single-element, and unknown-input cases.
- For anything classifying input into safe/unsafe categories: is there a
  test for an **unrecognised** input proving it takes the restrictive
  branch? Fail-closed behaviour is exactly what regresses silently.

#### Isolation and determinism

Does the test depend on execution order, on data another test created, on
wall-clock time, or on a fixed random value? Is `async: true` safe here —
does the test touch shared state (the database, the filesystem, an
application env value, a named process)?

Does it create the data it needs rather than assuming a seeded database?

#### Ash and Phoenix specifics

- A resource with an `AshAuthentication` policy bypass requires
  `context: %{private: %{ash_authentication?: true}}` to be exercised
  directly; without it the action is `Forbidden` in a test even though it
  works in the application.
- `Phoenix.ConnTest` sets `:plug_skip_csrf_protection`, so CSRF rejection
  is **not reproducible** in a controller test. A test claiming to cover
  it is misleading; the honest form is a comment saying it must be
  verified over real HTTP.
- Response headers, by contrast, *are* assertable in `ConnTest` — so a
  header-related fix has no excuse for going untested.
- Generating migrations for resources under `test/support` needs
  `MIX_ENV=test mix ash.codegen NAME`. Without the env it silently
  generates nothing, which looks like "no changes needed".

#### What the test says about the change

If a fix has no test, is that called out with a reason? "Not testable
here because X" is acceptable and useful. Silence is not.
