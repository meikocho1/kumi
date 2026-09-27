# kumi_storage

File and image uploads for Kumi, as an installable module. It generates a
**plain Ash resource** you own — not a wrapper, not a shorthand — and
kumi_admin picks it up automatically.

## Install

```elixir
# mix.exs
{:kumi, path: "../kumi"},
{:kumi_storage, path: "../kumi_storage"}
```

```bash
mix deps.get
mix kumi_storage.install
```

The installer composes `mix kumi.install` and then does three things:

1. Generates `lib/<app>/core/attachment.ex` — an ordinary
   `Ash.Resource` storing uploaded-file metadata, with an `:upload` action
   (`KumiStorage.Upload.prepare/3`: validation, then backend `store/4`)
   and a `__kumi_attachment_url__/1` URL function. Registered in
   `<App>.Core`.
2. Adds `config :kumi_storage, backend: KumiStorage.Backend.Local, root:
   "priv/uploads"` if nothing is configured yet, and adds
   `/priv/uploads/` to `.gitignore` so uploaded files are never committed.
   That root is relative to the working directory: in production, set an
   absolute one in `config/runtime.exs`.
3. Forwards a router path to `KumiStorage.Plug` (see
   [Backends](#backends) for its `config:` option), or prints the snippet
   if it can't find a router to edit.

`mix kumi.new my_app --with storage` does all of this at generation time.

## Use

In a `Kumi.Resource` shorthand block, an `:image` field expands to a
`belongs_to` targeting the generated Attachment resource:

```elixir
fields do
  field :name, :string, required: true
  field :avatar, :image, to: MyApp.Core.Attachment
end
```

`mix kumi.expand MyApp.Core.Person` prints exactly what that compiles to —
there is no hidden layer. In plain Ash, write the `belongs_to` yourself;
kumi_admin only needs the target resource to carry the
`__kumi_attachment__/0` marker.

## Validation

`KumiStorage.Validation.validate/4` runs at the storage boundary, **before**
the backend is called — backends do not validate.

| Check | Default | Override |
|---|---|---|
| Size cap | 10 MB | `:max_bytes` |
| Content-type allowlist | `image/jpeg`, `image/png`, `image/gif`, `image/webp` | `:allowed_content_types` |

The generated `:upload` action gets there through
`KumiStorage.Upload.prepare/3`, which:

- measures the size from the bytes themselves. A `:byte_size` the caller
  declares is ignored, so a false one can't get past the cap or be saved.
- calls the backend's `store/4` only once the action runs, inside the
  transaction, after the policies Ash can check up front. Building the
  changeset (a form validate, `Ash.can?/3`) stores nothing, and a caller
  those policies forbid never writes a file.
- deletes the stored file if the create fails after that. That includes a
  filter policy such as `authorize_if expr(owner_id == ^actor(:id))`: Ash
  checks it against the inserted row, so the file is written first, then
  the create is rolled back and the file deleted.
- reports a backend failure as a fixed "upload failed" error and logs the
  reason, so backend internals never reach the caller.

The content type is the caller's claim; see [Serving](#serving) for how
it is contained. The destroy action deletes the file only after the
transaction commits, and logs a delete that fails.

Both calls are library functions made from your plain Ash resource, so
fixes to them arrive with a dependency upgrade. An Attachment generated
before `KumiStorage.Upload` existed still has the old inline change
bodies, because the installer never overwrites the file: replace its
`:upload` and `:destroy` actions with the ones the installer generates
now, add `__kumi_storage_config__/0`, and give the router's forward its
`config:` option (see [Backends](#backends)); the plug refuses to
compile without it.

## Backends

`KumiStorage.Backend` is the behaviour; `KumiStorage.Backend.Local`
(filesystem) is the only v1 implementation. An S3 backend is a
planned follow-up rather than a speculative abstraction.

Every callback takes `opts` explicitly — backends never read Application
config themselves, and neither does any other kumi_storage module. The
config boundary is host code: the generated Attachment's
`__kumi_storage_config__/0` reads `config :kumi_storage, ...` and returns
`{backend, backend_opts}`. Its actions call it, and the router hands it to
the plug, which calls it once per request (so `config/runtime.exs` works):

```elixir
forward "/uploads", KumiStorage.Plug,
  config: {MyApp.Core.Attachment, :__kumi_storage_config__}
```

This keeps backends pure and directly testable, and matches the repo-wide
"library code takes explicit args" rule.

## Serving

`GET <mount>/:key` via `KumiStorage.Plug` — Plug only, no Phoenix
dependency. Security posture:

- The stored key's extension is derived from the **validated content
  type**, never from the client-supplied filename. An upload accepted as
  `image/png` cannot be stored or served as `.html`.
- A key resolving outside the backend root returns 404 —
  `Plug.Conn.send_file/3` never sees a path a client shouldn't reach.
- Every response, success and 404, carries `x-content-type-options:
  nosniff`.

### Access control

`/uploads/:key` is unauthenticated. The random key in the URL is the only
thing protecting a file: anyone holding the URL can fetch the bytes, with
no session and no actor. Ash policies on the Attachment, or on the record
that points at it, do not apply to the file itself.

Replacing an attachment or deleting its parent record does not unpublish
the old file; only destroying the Attachment deletes it. Don't serve
documents that must stay private this way without putting your own plug
or pipeline in front of the forward.

The generated `storage_key` attribute is `public? false`, so the key stays
out of public interfaces (`filter_input`, API extensions). Your own reads
still load it, which is what `__kumi_attachment_url__/1` uses.

## Development

```bash
mix deps.get
mix test
```

No database required.

## Part of the Kumi project

> Ash helps you model your application. Kumi helps you ship it as a product.

See the [root README](../README.md) for the other packages and
[CONTRIBUTING.md](../CONTRIBUTING.md) for setup and what a reviewer looks
for.

## License

MIT — see [`LICENSE`](LICENSE).
