defmodule Mix.Tasks.Nelly.MicWav do
  @moduledoc """
  Records microphone audio to a WAV file (no Whisper).

  Uses `config :nelly_assitant, :voice_pipeline` for PortAudio settings.

  ## Examples

      mix nelly.mic_wav
      mix nelly.mic_wav --seconds 5 --output /tmp/check.wav

  Disable `start_whisper_mic` in config while running this task so the mic is not already in use.
  """

  use Mix.Task

  @shortdoc "Record mic to WAV (Membrane debug)"

  @switches [
    output: :string,
    seconds: :integer
  ]

  @aliases [o: :output, s: :seconds]

  @default_output "mic_capture.wav"
  @default_seconds 3

  @impl Mix.Task
  def run(argv) do
    {parsed, _, _} = OptionParser.parse(argv, switches: @switches, aliases: @aliases)

    if Application.get_env(:nelly_assitant, :start_whisper_mic, false) do
      Mix.raise(
        ":start_whisper_mic is true — stop the app or set it to false so the microphone is free."
      )
    end

    Mix.Task.run("app.config")

    output = Keyword.get(parsed, :output, @default_output)
    seconds = Keyword.get(parsed, :seconds, @default_seconds)

    if seconds < 1 do
      Mix.raise("--seconds must be at least 1")
    end

    {:ok, _} = Application.ensure_all_started(:logger)
    {:ok, _} = Application.ensure_all_started(:membrane_file_plugin)
    {:ok, _} = Application.ensure_all_started(:membrane_wav_plugin)
    {:ok, _} = Application.ensure_all_started(:membrane_portaudio_plugin)

    pipeline_opts = Application.get_env(:nelly_assitant, :voice_pipeline, [])
    pipeline_opts = Keyword.put(pipeline_opts, :output, output)

    Mix.shell().info("Recording #{seconds}s to #{output} (Ctrl+C aborts)...")

    case Membrane.Pipeline.start_link(NellyAssitant.Whisper.Mic.MicToWavPipeline, pipeline_opts) do
      {:ok, _supervisor, pipeline} ->
        Process.sleep(seconds * 1000)
        :ok = Membrane.Pipeline.terminate(pipeline, timeout: 10_000, force?: true)
        Mix.shell().info("Done. Play the file with: aplay #{output} (Linux) or afplay (macOS).")

      {:error, reason} ->
        Mix.raise("failed to start mic WAV pipeline: #{inspect(reason)}")
    end
  end
end
