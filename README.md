# Cloister

**The helper application to manage cluster of nodes**

## Installation

* Add the dependency to your `mix.exs` file:

```elixir
def deps do
  [
    {:cloister, "~> 0.1"},
    ...
  ]
end
```

* Make sure both `:cloister` and `:libring` applications are configured properly in your `config.exs`

```elixir
config :cloister,
  sentry: ~w|node1@127.0.0.1 node2@127.0.0.1|a,
  consensus: 2

config :libring,
  rings: [
    cloister: [monitor_nodes: true]
  ]
```

* Make sure `:cloister` application is started. This does not require any action unless you have the list of applications specified explicitly. If so, add `:cloister` there.

---

## [Documentation](https://hexdocs.pm/cloister).

