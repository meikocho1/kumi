# Security policy

## Supported versions

Kumi is pre-1.0. Only the latest tagged release receives fixes; there are
no maintained backport branches yet. When 1.0 lands this section will say
which minor versions are supported and for how long.

## Reporting a vulnerability

**Please do not open a public issue for a security problem.**

Use GitHub's private vulnerability reporting on this repository:
**Security → Report a vulnerability**. That opens a private thread
visible only to the maintainers, and it works without anyone having to
publish an email address.

Please include:

- what an attacker can do, and what access they need to start;
- the smallest reproduction you have (a resource definition and a
  command is usually enough);
- the affected package (`kumi`, `kumi_admin`, `kumi_new`,
  `kumi_storage`) and version.

You should get an acknowledgement within a week. Kumi is maintained by a
very small number of people, so please allow time for a fix before any
public disclosure, and tell us if you have a disclosure deadline.

## Areas worth extra scrutiny

If you're looking for where the interesting surface is:

- **`mix kumi.apply`** executes DDL against a live database. It is
  restricted to changes classified SAFE, gated by an explicit allowlist of
  operation shapes, executes only statements that carry the whole change
  (no column type modifiers or index options dropped), runs in a single
  transaction, and re-introspects afterwards to verify the result. It
  also refuses to run outside `MIX_ENV=dev`, and while a migration is
  pending or `mix ash.codegen --check` fails. Any path that gets a
  destructive statement past those gates is a vulnerability, not a bug
  report.
- **`Kumi.Plan.Safety`** must fail closed: an unrecognised type change is
  classified DANGEROUS rather than assumed harmless. A case where it
  fails *open* is a security issue.
- **`kumi_storage`**'s upload path measures the size itself (the bytes of
  a binary, `File.stat/1` of a regular file; any other kind of path is
  rejected) and checks it and the content type before anything is stored,
  and stores only once the action runs, after the policies Ash can check
  up front. A filter policy Ash checks against the inserted row runs after
  the store, and a create it rejects is rolled back and its file deleted.
  The content type is the caller's claim: the stored extension is derived
  from it and every response carries `nosniff`, so an upload accepted as
  `image/png` is never served as HTML. The client filename is never used
  to build a path, and the `Plug` serves only keys that resolve inside the
  configured root. Served files are public to anyone holding the URL: the
  random key is the only access control, and Ash policies do not apply to
  the bytes. That is documented behaviour, not a vulnerability; a way to
  guess or enumerate keys is in scope, as are traversal, unrestricted type
  acceptance, or reading outside the configured root.
- **`kumi_admin`** deliberately has no authentication of its own — it
  consumes the host application's `on_mount` hooks and actor. Reads that
  bypass the host's Ash policies, or a rendered value escaping HTML
  encoding, are in scope. "The admin is reachable without logging in" is
  a host configuration issue unless the router macro itself is at fault.

## Out of scope

- Findings that require an already-compromised developer machine, or that
  require defeating the `MIX_ENV=dev` guard to run `mix kumi.apply` in
  production.
- Vulnerabilities in Ash, AshPostgres, Phoenix, or Postgres themselves —
  please report those upstream. We're glad to hear about them anyway if
  Kumi's usage makes them materially worse.
