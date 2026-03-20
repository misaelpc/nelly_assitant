defmodule Mix.Tasks.Nelly.Mic do
  @moduledoc "Runs live Whisper transcription from the default microphone."
  use Mix.Task

  @shortdoc "Run live Whisper mic transcription"

  @impl Mix.Task
  def run(_args) do
    Mix.Task.run("app.config")

    if Application.get_env(:nelly_assitant, :start_whisper_mic, false) do
      Mix.raise(
        ":start_whisper_mic is true — the Application already starts the mic pipeline. " <>
          "Disable it in config before running mix nelly.mic."
      )
    end

    Mix.Task.run("app.start")

    case Membrane.Pipeline.start_link(NellyAssitant.Whisper.Mic.LivePipeline, []) do
      {:ok, _supervisor, _pipeline} ->
        Process.sleep(:infinity)

      {:error, reason} ->
        Mix.raise("failed to start Whisper mic pipeline: #{inspect(reason)}")
    end
  end
end
