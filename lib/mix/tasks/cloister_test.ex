defmodule Mix.Tasks.Cloister.Test do
  @shortdoc "Run tests in Cloister"
  @moduledoc """
  Mix task to run test in previously started Cloister env.
  """

  use Mix.Task

  require Logger

  @consensus 3

  # elixir --name cloister_example_1@127.0.0.1 -S mix run --no-halt

  @impl Mix.Task
  @doc false
  def run(args) do
    {opts, [], pass_thru} =
      OptionParser.parse(args,
        strict: [application: :string, ip: :string, consensus: :integer, debug: :boolean]
      )

    application = Keyword.get(opts, :application, Mix.Project.config()[:app])
    if is_nil(application), do: raise("--application key is required")

    ip = Keyword.get(opts, :ip, "127.0.0.1")

    consensus =
      Keyword.get(opts, :consensus, Application.get_env(:cloister, :consensus, @consensus))
    consensus = consensus - 1

    Application.put_env(:cloister, :consensus, consensus)

    log_level = if Keyword.get(opts, :debug, false), do: :debug, else: :warning
    Logger.configure(level: log_level)

    this = :"#{application}_0@#{ip}"
    nodes = Enum.map(1..consensus, &:"#{application}_#{&1}@#{ip}")

    epmd_path = System.find_executable("epmd")
    epmd_port = Port.open({:spawn_executable, epmd_path}, [])
    elixir_path = System.find_executable("elixir")

    ports =
      Enum.map(nodes, fn node ->
        Port.open({:spawn_executable, elixir_path}, args: ~w|--name #{node} -S mix run --no-halt|)
      end)

    IO.inspect([empd: epmd_port, ports: Enum.map(ports, &Keyword.get(Port.info(&1), :os_pid))],
      label: "System PIDs"
    )

    Node.start(this)
    Mix.Tasks.Test.run(pass_thru)

    # Enum.each(ports, &Port.close/1)
    # Port.close(epmd_port)

    for port <- [epmd_port | ports],
        info when is_list(info) <- [Port.info(port)],
        pid = Keyword.get(info, :os_pid) do
      # -TERM would be kinda better, but is spits garbage to stdout
      System.at_exit(fn _ -> System.shell("kill -KILL #{pid} 2>&1 >/dev/null") end)
    end
  end
end
