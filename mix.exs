defmodule Cloister.MixProject do
  use Mix.Project

  @app :cloister
  @version "0.3.3"

  def project do
    [
      app: @app,
      version: @version,
      elixir: "~> 1.9",
      elixirc_paths: elixirc_paths(Mix.env()),
      compilers: compilers(Mix.env()),
      start_permanent: Mix.env() == :prod,
      preferred_cli_env: ["test.cluster": :test],
      xref: [exclude: []],
      description: description(),
      package: package(),
      deps: deps(),
      aliases: aliases(),
      xref: [exclude: []],
      docs: docs(),
      releases: [
        cloister: [
          include_executables_for: [:unix],
          applications: [logger: :permanent, runtime_tools: :permanent]
        ]
      ],
      dialyzer: [
        plt_file: {:no_warn, ".dialyzer/plts/dialyzer.plt"},
        ignore_warnings: ".dialyzer/ignore.exs"
      ]
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      applications: [:logger, :libring],
      mod: {Cloister.Application, []},
      start_phases: [{:warming_up, []}],
      registered: [Cloister, Cloister.Node, Cloister.Manager]
    ]
  end

  defp deps do
    [
      {:libring, "~> 1.0"},
      {:boundary, "~> 0.4", runtime: false},
      # dev / test
      {:test_cluster_task, "~> 0.5", only: [:dev, :test, :ci]},
      {:dialyxir, "~> 1.0.0", only: [:dev, :test, :ci]},
      {:credo, "~> 1.0", only: [:dev, :ci], runtime: false},
      {:ex_doc, "~> 0.11", only: :dev, runtime: false}
    ]
  end

  defp aliases do
    [
      quality: ["format", "credo --strict", "dialyzer"],
      "quality.ci": [
        "format --check-formatted",
        "credo --strict",
        "dialyzer"
      ],
      test: ["test.cluster"]
    ]
  end

  defp description do
    """
    The helper application to manage cluster, that uses hash ring to route requests to nodes.

    Automatically keeps track of connected nodes, provides helpers
    to determine where the term is to be executed, to multicast to all the nodes
    in the cluster and to retrieve current state of the cluster.
    """
  end

  defp package do
    [
      name: @app,
      files: ~w|config stuff lib mix.exs README.md|,
      maintainers: ["Aleksei Matiushkin"],
      licenses: ["MIT"],
      links: %{
        "GitHub" => "https://github.com/am-kantox/#{@app}",
        "Docs" => "https://hexdocs.pm/#{@app}"
      }
    ]
  end

  defp docs do
    [
      main: "readme",
      source_ref: "v#{@version}",
      canonical: "http://hexdocs.pm/#{@app}",
      logo: "stuff/cloister-48x48.png",
      source_url: "https://github.com/am-kantox/#{@app}",
      assets: "stuff/images",
      extras: ["README.md", "stuff/configuration.md"],
      groups_for_modules: []
    ]
  end

  def compilers(:dev), do: [:boundary | Mix.compilers()]
  def compilers(_), do: Mix.compilers()

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(:ci), do: ["lib", "test/support"]
  #  defp elixirc_paths(:dev), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]
end
