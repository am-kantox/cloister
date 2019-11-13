import Config

config :cloister,
  sentry: ~w|foo_1@127.0.0.1 inexisting@127.0.0.1|a,
  consensus: 2

config :libring,
  rings: [
    # A ring which automatically changes based on Erlang cluster membership
    # Shall I node_blacklist: [:sentry] here?
    cloister: [monitor_nodes: true]
  ]
