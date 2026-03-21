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

    pipeline_opts =
      :nelly_assitant
      |> Application.get_env(:voice_pipeline, [])
      |> Keyword.put(:output, output)
      |> Keyword.put(:record_seconds, seconds)

    Mix.shell().info("Recording #{seconds}s to #{output} (graceful stop + WAV finalize)...")

    case Membrane.Pipeline.start_link(NellyAssitant.Whisper.Mic.MicToWavPipeline, pipeline_opts) do
      {:ok, _supervisor, pipeline} ->
        ref = Process.monitor(pipeline)

        receive do
          {:DOWN, ^ref, :process, _pid, :normal} ->
            :ok

          {:DOWN, ^ref, :process, _pid, reason} ->
            Mix.shell().error("pipeline exited: #{inspect(reason)}")
        after
          seconds * 1000 + 30_000 ->
            _ = Membrane.Pipeline.terminate(pipeline, timeout: 5000, force?: true)
            Mix.raise("timeout waiting for pipeline shutdown after recording")
        end

        Mix.shell().info(
          "Done. Linux: aplay #{output}  (or ffplay). If silent, remove :channels from :voice_pipeline (use device default)."
        )

      {:error, reason} ->
        Mix.raise("failed to start mic WAV pipeline: #{inspect(reason)}")
    end
  end
end
