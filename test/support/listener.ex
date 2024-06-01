defmodule Cloister.Listener.Default do
  @moduledoc false

  @behaviour Cloister.Listener
  require Logger

  @impl Cloister.Listener
  def on_state_change(from, to, state) do
    Logger.debug(
      "[🕸️ @:#{node()}] ♻  from: " <>
        inspect(from) <> ", to: " <> inspect(to) <> ", state: " <> inspect(state)
    )
  end
end
