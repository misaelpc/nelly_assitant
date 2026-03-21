defmodule Mix.Tasks.Nelly.MicWav do
  @moduledoc """
  Records microphone audio to **raw PCM** (no Whisper, no WAV header).

  Uses `config :nelly_assitant, :voice_pipeline` for PortAudio settings. Convert with `ffmpeg`, e.g.:

      ffmpeg -f s16le -ar 44100 -ac 2 -i mic_capture.raw out.wav

  (Use the same `-ar` / `-ac` / sample format as your `:voice_pipeline`.)

  ## Examples

      mix nelly.mic_wav
      mix nelly.mic_wav --seconds 5 --output /tmp/check.raw

  Disable `start_whisper_mic` in config while running this task so the mic is not already in use.
  """

  use Mix.Task

  @shortdoc "Record mic to raw PCM (Membrane debug)"

  @switches [
    output: :string,
    seconds: :integer
  ]

  @aliases [o: :output, s: :seconds]

  @default_output "mic_capture.raw"
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
    {:ok, _} = Application.ensure_all_started(:membrane_portaudio_plugin)

    pipeline_opts =
      :nelly_assitant
      |> Application.get_env(:voice_pipeline, [])
      |> Keyword.put(:output, output)
      |> Keyword.put(:record_seconds, seconds)

    Mix.shell().info("Recording #{seconds}s to #{output} (raw PCM, graceful stop)...")

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
          "Done. Check file size / logs for byte count. Convert: ffmpeg -f s16le -ar <rate> -ac <ch> -i #{output} out.wav"
        )

      {:error, reason} ->
        Mix.raise("failed to start mic WAV pipeline: #{inspect(reason)}")
    end
  end
end
