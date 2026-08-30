# kumi_new

`mix kumi.new` — generates a running Phoenix+Ash app with Kumi installed.

```bash
cd kumi_new && mix archive.build && mix archive.install  # confirm the [Yn] prompt
mix kumi.new my_crm --kumi-path .. --db-port 5434
```

Flags: `--kumi-path DIR` (required until Kumi is on Hex), `--db-port PORT`
(default 5432), `--no-admin`, `--no-setup`, `--json-api`,
`--auth-strategy` (csv of `password` / `magic_link` / `api_key`,
default `password` — see [`../kumi/guides/auth.md`](../kumi/guides/auth.md)).

## License

MIT — see [`LICENSE`](LICENSE).
