defmodule NellyAssitant.MixProject do
  use Mix.Project

  def project do
    [
      app: :nelly_assitant,
      version: "0.1.0",
      elixir: "~> 1.18",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      mod: {NellyAssitant.Application, []},
      extra_applications: [:logger]
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:membrane_whisper_plugin, "~> 0.1.0"},
      {:membrane_portaudio_plugin, "~> 0.19.4"},
      {:membrane_ffmpeg_swresample_plugin, "~> 0.20.5"}
    ]
  end
end
