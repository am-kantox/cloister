import Config

config :cloister,
  sentry: ~w|cloister_0@127.0.0.1 cloister_1@127.0.0.1 cloister_2@127.0.0.1 cloister_3@127.0.0.1 cloister_4@127.0.0.1|a,
  consensus: 1,
  additional_modules: [Cloister.Void]
