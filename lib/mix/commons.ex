defmodule Cloister.Mix.Commons do
  @moduledoc false

  @consensus 3

  defp options(opts) do
    application =
      Keyword.get(
        opts,
        :application,
        Application.get_env(:cloister, :otp_app, Mix.Project.config()[:app])
      )

    if is_nil(application), do: raise("--application key is required")

    consensus =
      Keyword.get(opts, :consensus, Application.get_env(:cloister, :consensus, @consensus))

    ip = Keyword.get(opts, :ip, "127.0.0.1")

    %{application: application, ip: ip, consensus: consensus}
  end

  def node_name(opts \\ [], id) do
    %{application: application, ip: ip} = options(opts)
    :"#{application}_#{id}@#{ip}"
  end

  def nodes(opts \\ []) do
    %{consensus: consensus} = options(opts)
    Enum.map(0..consensus, &node_name(opts, &1))
  end

  def spawn_nodes(opts \\ []) do
    elixir_path = System.find_executable("elixir")

    opts
    |> nodes()
    |> tl()
    |> Enum.map(fn node ->
      Port.open({:spawn_executable, elixir_path},
        args: ~w|--name #{node} -S mix run --no-halt|,
        env: [{~c"MIX_ENV", ~c"cloister"}]
      )
    end)
  end

  def spawn_epmd do
    epmd_path = System.find_executable("epmd")
    Port.open({:spawn_executable, epmd_path}, [])
  end

  def spawn_this(opts \\ []) do
    opts
    |> nodes()
    |> hd()
    |> Node.start()
  end

  def cleanup(ports) do
    for port <- ports,
        info when is_list(info) <- [Port.info(port)],
        pid = Keyword.get(info, :os_pid) do
      # -TERM would be kinda better, but is spits garbage to stdout
      System.at_exit(fn _ -> System.shell("kill -KILL #{pid} 2>&1 >/dev/null") end)
    end
  end

  @config "cloister.exs"
  @config_path Path.join("config", @config)

  def config? do
    if File.exists?(@config_path) do
      true
    else
      Mix.shell().error([
        :yellow,
        "* #{@config_path} ",
        :reset,
        "is required (run ",
        :magenta,
        "mix cloister.init",
        :reset,
        ")"
      ])

      false
    end
  end

  def gen_config(opts) do
    if File.exists?(@config_path) do
      Mix.shell().info([:yellow, "* creating #{@config_path} ", :reset, "file already esists"])
    else
      assigns = options(opts)

      listener =
        assigns.application
        |> to_string()
        |> Macro.camelize()
        |> Module.concat("Cloister.Listener")

      assigns =
        assigns
        |> Map.put(:listener, listener)
        |> Map.put_new(:log_level, :debug)
        |> Map.to_list()

      File.mkdir("config")
      Mix.Generator.copy_template(Path.expand("cloister.eex", __DIR__), @config_path, assigns)

      Mix.shell().info([
        :green,
        "* config/test.exs ",
        :reset,
        "maybe amend adding ",
        :magenta,
        "import_config \"#{@config}\""
      ])
    end
  end
end
