import Config

config :cloister, :sentry, ~w|foo_1@127.0.0.1 inexisting@127.0.0.1|a

config :cloister, :roles, [
  {:"foo_1@127.0.0.1", [:proposer]},
  {:"foo_2@127.0.0.1", [:proposer]},
  {:"foo_3@127.0.0.1", [:proposer]}
]
