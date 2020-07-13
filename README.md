# Cloister

![Test](https://github.com/am-kantox/cloister/workflows/Test/badge.svg)  ![Dialyzer](https://github.com/am-kantox/cloister/workflows/Dialyzer/badge.svg)    **The helper application to manage cluster of nodes**

## Installation

* Add the dependency to your `mix.exs` file:

```elixir
def deps do
  [
    {:cloister, "~> 0.5"},
    ...
  ]
end
```

* Make sure both `:cloister` and `:libring` applications are configured properly in your `config.exs`

```elixir
config :cloister,
  sentry: ~w|node1@127.0.0.1 node2@127.0.0.1|a,
  consensus: 2
```

* Make sure `:cloister` application is started. This does not require any action unless you have the list of applications specified explicitly. If so, add `:cloister` there.

## Changelog

- **`0.6.0`** support many hashrings within the same cloister
- **`0.2.0`** use `Application.c:start_phase/3` callback to postpone application start until the consensus is reached


---

## [Documentation](https://hexdocs.pm/cloister).

