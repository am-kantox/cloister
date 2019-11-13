defmodule Cloister do
  @moduledoc """
  `Cloister` is a consensus handler for clusters.
  """

  use DynamicSupervisor

  @spec start_link(opts :: keyword()) :: Supervisor.on_start()
  def start_link(opts \\ []) do
    {name, opts} = Keyword.pop(opts, :name, __MODULE__)
    DynamicSupervisor.start_link(__MODULE__, opts, name: name)
  end

  @impl DynamicSupervisor
  def init(opts),
    do: DynamicSupervisor.init(Keyword.merge([strategy: :one_for_one], opts))
end
