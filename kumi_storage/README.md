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
   (validation + backend `store/4`) and a `__kumi_attachment_url__/1` URL
   function. Registered in `<App>.Core`.
2. Adds `config :kumi_storage, backend: KumiStorage.Backend.Local, root:
   "priv/uploads"` if nothing is configured yet.
3. Forwards a router path to `KumiStorage.Plug`, or prints the snippet if
   it can't find a router to edit.

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

## Backends

`KumiStorage.Backend` is the behaviour; `KumiStorage.Backend.Local`
(filesystem) is the only v1 implementation. An S3 backend is a committed
follow-up, not a speculative abstraction.

Every callback takes `opts` explicitly — backends never read Application
config themselves. `KumiStorage.Plug` is the config-reading boundary: it
resolves `config :kumi_storage, ...` once per request and passes the result
down. This keeps backends pure and directly testable, and matches the
repo-wide "library code takes explicit args" rule.

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
