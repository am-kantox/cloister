defmodule Cloister.MixProject do
  use Mix.Project

  @app :cloister
  @version "0.17.1"

  def project do
    [
      app: @app,
      version: @version,
      elixir: "~> 1.16",
      elixirc_paths: elixirc_paths(Mix.env()),
      compilers: compilers(Mix.env()),
      start_permanent: Mix.env() == :prod,
      prune_code_paths: Mix.env() == :prod,
      preferred_cli_env: [enfiladex: :test, "enfiladex.ex_unit": :test, "cloister.test": :test],
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
        plt_add_deps: :app_tree,
        plt_add_apps: [:mix, :nimble_options],
        list_unused_filters: true,
        ignore_warnings: ".dialyzer/ignore.exs"
      ]
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger, :libring],
      mod: {Cloister.Application, []},
      start_phases: [warming_up: [], rehash_on_up: []],
      registered: [Cloister, Cloister.Node, Cloister.Manager]
    ]
  end

  defp deps do
    [
      {:libring, "~> 1.0"},
      {:finitomata, "~> 0.7"},
      {:nimble_options, "~> 0.2 or ~> 1.0"},
      # dev / test
      {:enfiladex, "~> 0.2", only: [:dev, :test]},
      {:dialyxir, "~> 1.1", only: [:dev, :ci], runtime: false},
      {:credo, "~> 1.0", only: [:dev, :ci], runtime: false},
      {:ex_doc, "~> 0.11", only: :dev}
    ]
  end

  defp aliases do
    [
      quality: ["format", "credo --strict", "dialyzer"],
      "quality.ci": [
        "format --check-formatted",
        "credo --strict",
        "dialyzer"
      ]
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
      files: ~w|config stuff lib mix.exs README.md LICENSE|,
      maintainers: ["Aleksei Matiushkin"],
      licenses: ["Kantox LTD"],
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
      assets: "stuff/img",
      extras: ["README.md" | Path.wildcard("stuff/*.md")],
      groups_for_modules: []
    ]
  end

  def compilers(_), do: [:finitomata | Mix.compilers()]

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(:ci), do: ["lib", "test/support"]
  #  defp elixirc_paths(:dev), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]
end
