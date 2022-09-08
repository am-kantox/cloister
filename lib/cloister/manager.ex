defmodule Cloister.Manager do
  @moduledoc """
  Use this module to start _Cloister_ manually inside the application
  supervision tree instead of running it as an application (default.)

  This is not recommended and requires better understanding of internals.
  Also, `:cloister` must be put into `:included_applications` section
  of your application `mix.exs` to prevent the application from starting up
  during the dependent applications starting phase.
  """

  use Supervisor
  require Logger

  @doc "Starts the cloister manager process in the supervision tree"
  @spec start_link(opts :: keyword()) :: GenServer.on_start()
  def start_link(opts) do
    :ok = Application.ensure_started(:libring, :permanent)

    {state, opts} = Keyword.pop(opts, :state, [])
    Supervisor.start_link(__MODULE__, state, Keyword.put_new(opts, :name, __MODULE__))
  end

  @doc false
  @impl Supervisor
  def init(state) do
    state = Keyword.put_new(state, :otp_app, Application.get_env(:cloister, :otp_app, :cloister))

    {monitor_opts, state} = Keyword.pop(state, :monitor_opts, [])

    {additional_modules, state} =
      Keyword.pop(
        state,
        :additional_modules,
        Application.get_env(:cloister, :additional_modules, [])
      )

    {additional_modules, failed_modules} =
      Enum.split_with(additional_modules, &ensure_compiled?/1)

    if failed_modules != [],
      do: Logger.warn("Following configured modules failed to start: " <> inspect(failed_modules))

    children =
      [
        {Cloister.Monitor, [{:state, state} | monitor_opts]},
        Cloister,
        Cloister.Node
      ] ++ additional_modules

    Supervisor.init(children, strategy: :rest_for_one)
  end

  @spec ensure_compiled?(module()) :: boolean()
  defp ensure_compiled?(module),
    do: match?({:module, ^module}, Code.ensure_compiled(module))
end
