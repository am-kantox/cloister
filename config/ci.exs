import Config

config :cloister,
  sentry: ~w|cloister-foo-0@127.0.0.1 inexisting@127.0.0.1|a,
  consensus: 4,
  additional_modules: [Cloister.Void]

config :libring,
  rings: [
    # A ring which automatically changes based on Erlang cluster membership
    # Shall I node_blacklist: [:sentry] here?
    cloister: [monitor_nodes: true]
  ]
