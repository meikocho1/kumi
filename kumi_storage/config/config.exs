import Config

# Ash.DataLayer.Ets (test/support) logs every write at :debug.
if config_env() == :test do
  config :logger, level: :warning
end
