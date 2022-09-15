defmodule Cloister.Listener.Default do
  @moduledoc false

  @behaviour Cloister.Listener
  require Logger

  def on_state_change(from, state) do
    Logger.debug("[🕸️ @:#{node()}] 🔄 from: " <> inspect(from) <> ", state: " <> inspect(state))
  end
end
