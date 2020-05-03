defmodule Cloister.Manager do
  @moduledoc false
  use Supervisor

  @spec start_link(opts :: keyword()) :: GenServer.on_start()
  def start_link(opts) do
    :ok = Application.ensure_started(:libring, :permanent)

    {state, opts} = Keyword.pop(opts, :state, [])
    Supervisor.start_link(__MODULE__, state, Keyword.put_new(opts, :name, __MODULE__))
  end

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

    additional_modules = Enum.filter(additional_modules, &ensure_compiled?/1)

    children =
      [
        {Cloister.Monitor, [{:state, state} | monitor_opts]},
        Cloister,
        Cloister.Node
      ] ++ additional_modules

    Supervisor.init(children, strategy: :rest_for_one)
  end

  defp ensure_compiled?(module),
    do: match?({:module, ^module}, Code.ensure_compiled(module))
end
