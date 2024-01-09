# Cloister    [![Kantox ❤ OSS](https://img.shields.io/badge/❤-kantox_oss-informational.svg)](https://kantox.com/)  ![Test](https://github.com/am-kantox/cloister/workflows/Test/badge.svg)  ![Dialyzer](https://github.com/am-kantox/cloister/workflows/Dialyzer/badge.svg)

**The helper application to manage cluster of nodes.**

## Installation

- Add the dependency to your `mix.exs` file:

```elixir
def deps do
  [
    {:cloister, "~> 0.5"},
    ...
  ]
end
```

- Make sure both `:cloister` and `:libring` applications are configured properly in your `config.exs`

```elixir
config :cloister,
  sentry: ~w|node1@127.0.0.1 node2@127.0.0.1|a,
  consensus: 2
```

- Make sure `:cloister` application is started. This does not require any action unless you have the list of applications specified explicitly. If so, add `:cloister` there.

## Changelog

- **`0.17.0`** [TST] shortnames, proper testing with `enfiladex`
- **`0.16.0`** [EXP] experimental `mix` tasks to test/run stuff in a cloister
- **`0.15.0`** [BUG] fixed `Cloister.multicast/multicall`
- **`0.14.0`** named isolated `Finitomata` supervision tree
- **`0.13.0`** [BUG] fixed `Cloister.state/0` adding groups (credits: @anthony-gonzalez-kantox)
- **`0.12.0`** complete rewrite of cluster assembly based on `Finitomata`
- **`0.10.0`** `Cloister.siblings!/0` and `Cloister.consensus/0`, better tests
- **`0.9.0`** `Cloister.multiapply/4` to wrap `:rpc.multicall/4`
- **`0.7.0`** `magic? :: boolean()` and `loopback? :: boolean()` config params to avoid cluster building in tests
- **`0.6.0`** support many hashrings within the same cloister
- **`0.2.0`** use `Application.c:start_phase/3` callback to postpone application start until the consensus is reached

---

## [Documentation](https://hexdocs.pm/cloister).
