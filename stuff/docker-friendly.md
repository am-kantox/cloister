# Docker Friendly

_Cloister_ is being developed with the drop-in support of [_Docker_](https://www.docker.com/). Distributed _Erlang_ is a charm to work with unless your _DevOps_ team is engaged in containerizing the whole universe. They usually have many cryptic arguments full of words you as an old-school software engineer would barely understand, and sooner or later you are faced with a fact that now we run everything in a dockerized environment, which means no one can guarantee your application has an IP/DNS, or would not have automatically restarted depending on the current moon phase.

I am exaggerating a bit, but this is it: you cannot prepare the release hardcoding longnames in `vm.args` and/or `env.sh` anymore. You should be ready to handle spontaneous restarts of containers (and therefore your _ErlangVM_ instances) gracefully. And you are probably still in a need to test it locally, as well as in containerized environment.

That is where `cloister` might step into to help. It takes care about the cluster handling, based on either the list of node names (IP/DNS, old school,) or a service name exposed by docker. It uses [`Application.start_phase/3`](https://hexdocs.pm/elixir/Application.html?#c:start_phase/3) to ensure the cluster is started _before_ letting the boot process to continue. It also provides a callback when the topology of the cluster changes (new node added, node shut down, etc.)

## Dev Environment, no Docker

All one needs to start playing with `cloister` is to add a dependency to `mix.exs` file and put some config:

```elixir
config :cloister,
  otp_app: :cloister_test,
  sentry: ~w|node1@127.0.0.1 node2@127.0.0.1|a,
  consensus: 1
```

That config would instruct _Cloister_ to use `:cloister_test` as the main _OTP_ app _and_ the name of the [`HashRing`](https://github.com/bitwalker/libring) behind. It would expect nodes `:"node1@127.0.0.1"` and `:"node2@127.0.0.1"` to exist and it’ll try to connect to them, but as soon as it sees itself, and `consensus` parameter is set to `1`, it won’t worry about others and report the successful cluster assembly.

![:nonode@nohost startup](assets/cloister-nonode-startup.png)

---

## Test Environment, no Docker

To test the distributed environment outside of _Docker_, one might use [`test_cluster_task`](https://github.com/am-kantox/test_cluster_task) package that effectively starts the distributed environment before running tests. To use it, simply add `{:test_cluster_task, "~> 0.3"}` to the dependencies list of your application and use `mix test.cluster` _or_ set the alias in `mix.exs` project:

```elixir
def project do
  [
    ...,
    aliases: [test: ["test.cluster"]]
  ]
end
```

![:"cloister_test_0@127.0.0.1" startup](assets/cloister-test-startup.png)

---

## Releases for Docker Environment

OK, now it’s time to add _Docker_ to the equation. _Cloister_ is smart enough to distinguish the list of node vs. the service name when passed to `:sentry` config option. When it’s an atom, _Cloister_ will shut down the `:net_kernel` application and restart it in distributed mode. For that to work, one must explicitly specify `export RELEASE_DISTRIBUTION=none` in `rel/env.sh.eex` file for releases.

Our config would now look like:

```elixir
config :cloister,
  otp_app: :cloister_test,
  sentry: :"cloister_test.local",
  consensus: 3
```

Here, `:"cloister_test.local"` is the name of service to be used for nodes discovery _and_ at least three nodes up would be expected for it to pass the _warming_ phase. The application startup chain would be blocked until at least three nodes are up and connected.

We would also need a `Dockerfile` which is the typical one, built from `elixir:$ELIXIR_VERSION` and with `epmd -d` _explicitly started_ before the application itself. Also we’d need `docker-compose.yml`, declaring the service like below.

```yaml
version: '3.1'

services:
  cloister_test:
    build: .
    networks:
      local:
        aliases:
          - cloister_test.local
    environment:
      - CLOISTER_TEST_CLUSTER_ADDRESS=cloister_test.local

networks:
  local:
    driver: bridge
```

Once done, one might build the composed image and start it with three instances of the application:

```sh
docker-compose build
docker-compose up --scale cloister_test=3 --remove-orphans
```

After some debug info, it’d spit out:

![:"cloister_test@172.26.0.*" startup](assets/cloister-docker-startup.png)

All three instances are up and connected, ready to perform their work.

---

## Tips and Tweaks

_Cloister_ relies mainly on configuration because it’s started as a separate application _before_ the main _OTP_ application that uses it and relies on startup phases to block until the consensus is reached. For the very fine tuning, one might put `:cloister` into `:included_applications` _and_ embed `Cloister.Manager` manually into the supervision tree. See `Cloister.Application.start_phase/3` for the inspiration on how to wait till consensus is reached.

Also, one might start and manage `HashRing` on their own by setting `:ring` option in `config`. _Cloister_ would expect the ring to be started and handled by the consumer application.

The whole configuration is described on [_Configuration_](configuration.html) page.