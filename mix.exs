defmodule ExQuillDeltaToHtmlConverter.MixProject do
  use Mix.Project

  def project do
    [
      app: :ex_quill_delta_to_html_converter,
      version: "0.1.0",
      elixir: "~> 1.15",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger]
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:ecto_enum, "~> 1.4.0"},
      {:html_entities, "~> 0.5.2"},
      {:jason, "~> 1.4.1"},
      # {:dep_from_git, git: "https://github.com/elixir-lang/my_dep.git", tag: "0.1.0"}
    ]
  end
end
