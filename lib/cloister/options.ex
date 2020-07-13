defmodule Cloister.Options do
  @moduledoc false

  @spec sentry(any()) :: {:ok, [atom()] | atom()} | {:error, binary()}
  @doc false
  def sentry(value) do
    case value do
      [_ | _] = _nodes ->
        {:ok, value}

      service when is_atom(service) ->
        {:ok, value}

      _other ->
        {:error,
         "Value for :sentry must be a list of nodes or an atom representing the name of the service"}
    end
  end

  @doc false
  @spec additional_modules(any()) :: {:ok, [module()]} | {:error, binary()}
  def additional_modules(value) do
    case value do
      [_ | _] = modules ->
        # if Enum.all?(modules, &match?({:module, ^&1}, Code.ensure_compiled(&1))),
        if Enum.all?(modules, &is_atom/1),
          do: {:ok, value},
          else: {:error, "All modules specified as additional must be available"}

      _other ->
        {:error, "Value for :additional_modules must be a list of modules"}
    end
  end

  @schema [
    otp_app: [
      type: :atom,
      default: :cloister,
      doc: "OTP application this cloister runs for."
    ],
    sentry: [
      required: true,
      type: {:custom, Cloister.Options, :sentry, []},
      doc: """
      The way the cloister knows how to build cluster; might be a service name or a node list.
      E. g. `:"cloister.local"` or `~w[c1@127.0.0.1 c2@127.0.0.1]a`. Default `[node()]`.
      """
    ],
    consensus: [
      required: true,
      type: :non_neg_integer,
      default: 1,
      doc: "Number of nodes to consider consensus."
    ],
    listener: [
      type: :atom,
      default: Cloister.Listener.Default,
      doc: "Listener to be called when the ring is changed."
    ],
    additional_modules: [
      type: {:custom, Cloister.Options, :additional_modules, []},
      doc: "Additional modules to include into `Cloister.Manager`’s supervision tree."
    ],
    ring: [
      type: :atom,
      doc: """
      The name of the `HashRing` to be used.
      If set, the _HashRing_ is assumed to be managed externally.
      """
    ],
    manager: [
      doc: "Set of options to configure `Cloister.Manager` when started in a supervision tree.",
      type: :non_empty_keyword_list,
      keys: [
        name: [type: :atom, doc: "Name of the `Manager` process."],
        state: [
          type: :non_empty_keyword_list,
          keys: [
            otp_app: [required: true, type: :atom],
            additional_modules: [
              type: {:custom, Cloister.Options, :additional_modules, []}
            ]
          ],
          doc: "The parameters to configure the `Manager` ouside of `Cloister` application."
        ]
      ]
    ],
    monitor_opts: [
      doc: "Fine `Cloister.Monitor`’s tuning.",
      type: :non_empty_keyword_list,
      keys: [
        name: [required: true, type: :atom, doc: "Name of the `Monitor` process."]
      ]
    ]
  ]

  @doc false
  @spec schema :: NimbleOptions.schema()
  def schema, do: @schema
end

NimbleOptions.validate!(Application.get_all_env(:cloister), Cloister.Options.schema())
