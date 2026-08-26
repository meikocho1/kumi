import Config

# Test-only Ash harness (test/support): this is what the package's own
# tests exercise Kumi.Desired.extract/1 and Kumi.Actual.introspect/1
# against. Kumi's library code never reads this config — only test/support
# and the test files themselves do.
config :kumi, ecto_repos: [Kumi.Test.Repo]
config :kumi, ash_domains: [Kumi.Test.Domain]

config :kumi, Kumi.Test.Repo,
  username: "postgres",
  password: "postgres",
  hostname: "localhost",
  port: 5434,
  database: "kumi_test#{System.get_env("MIX_TEST_PARTITION")}",
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: System.schedulers_online() * 2

config :logger, level: :warning
