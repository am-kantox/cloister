import Config

config :cloister,
  sentry: ~w|cloister@127.0.0.1 cloister_1@127.0.0.1|a,
  consensus: 2,
  loopback?: true,
  additional_modules: [Cloister.Void]
