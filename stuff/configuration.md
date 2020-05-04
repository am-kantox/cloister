# Configuration

_Cloister_ is another cluster support library that aims to be a drop-in for cluster support in distributed environment.

It relies mainly on configuration because it’s started as a separate application _before_ the main _OTP_ application that uses it and relies on startup phases to block until the consensus is reached. For the very fine tuning, one might put `:cloister` into `:included_applications` _and_ embed `Cloister.Manager` manually into the supervision tree. See `Cloister.Application.start_phase/3` for the inspiration on how to wait till consensus is reached.

On a bird view, the config might look like:

```elixir
config :cloister,
  # OTP application this cloister runs for
  otp_app: :my_app,                    # default: :cloister

  # the way the cloister knows how to build cluster
  sentry: :"cloister.local",           # service name
  # or node list (default `[node()]`)
  # sentry: ~w[c1@127.0.0.1 c2@127.0.0.1]a

  # number of nodes to consider consensus
  consensus: 3,                        # default

  # listener to be called when the ring is changed
  listener: MyApp.Listener,            # default: Stub

  # monitor to handle ring changes / don’t override
  monitor: MyApp.Monitor,              # default: Stub

  # monitor options to pass to a monitor when created
  monitor_opts: [
    name: MyMonitor                    # default: monitor.name
  ]

  # additional modules to include into `Manager`’s supervision tree
  additional_modules: [Cloister.Void], # useful for tests / dev

  # the name of the `HashRing` to be used
  # if set, the _HashRing_ is assumed to be managed externally
  ring: :cloister,                     # default

  # manager configuration, used when cloister app is not started
  manager: [
    name: Cloister.Manager,            # default
    state: [
      otp_app: :my_app,                # default: :cloister
      additional_modules: []           # additional modules as above
    ]
  ]
```