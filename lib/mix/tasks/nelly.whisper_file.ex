defmodule Mix.Tasks.Nelly.WhisperFile do
  @moduledoc """
  Transcribe an audio file with Bumblebee Whisper (no microphone, no Membrane pipeline).

  Uses ffmpeg (in PATH) to decode; supports common formats (WAV, MP3, …). Measures wall time so you
  can compare Pi vs desktop without PortAudio.

  Merges `config :nelly_assitant, :voice_pipeline` with CLI flags (`whisper_hf_repo`, language,
  compile options, etc. apply).

  ## Examples

      mix nelly.whisper_file /tmp/mic_capture.wav
      mix nelly.whisper_file /path/audio.mp3 --repo openai/whisper-base
      mix nelly.whisper_file clip.wav --chunk-seconds 15
  """

  use Mix.Task

  @shortdoc "Transcribe a file with Whisper (benchmark / sanity check)"

  @switches [
    repo: :string,
    chunk_seconds: :integer
  ]

  @aliases [r: :repo, c: :chunk_seconds]

  @impl Mix.Task
  def run(argv) do
    {parsed, paths, _} = OptionParser.parse(argv, switches: @switches, aliases: @aliases)

    path =
      case paths do
        [p | _] -> Path.expand(p)
        [] -> Mix.raise("usage: mix nelly.whisper_file PATH [options]\n\nSee: mix help nelly.whisper_file")
      end

    unless File.exists?(path) do
      Mix.raise("file not found: #{path}")
    end

    if Application.get_env(:nelly_assitant, :start_whisper_mic, false) do
      Mix.raise(
        ":start_whisper_mic is true — set it to false for this task (avoids starting the live mic pipeline)."
      )
    end

    Mix.Task.run("app.config")
    Mix.Task.run("app.start")

    merged =
      :nelly_assitant
      |> Application.get_env(:voice_pipeline, [])
      |> maybe_put(:whisper_hf_repo, Keyword.get(parsed, :repo))
      |> maybe_put(:whisper_file_chunk_seconds, Keyword.get(parsed, :chunk_seconds))

    Mix.shell().info("Loading Whisper + transcribing #{path} …")

    serving = NellyAssitant.Whisper.WhisperServing.build_for_file(merged)

    {microseconds, result} =
      :timer.tc(fn ->
        Nx.Serving.run(serving, {:file, path})
      end)

    text =
      case result do
        %{chunks: chunks} when is_list(chunks) ->
          chunks |> Enum.map_join("", & &1.text) |> String.trim()

        other ->
          Mix.raise("unexpected serving output: #{inspect(other)}")
      end

    elapsed_ms = div(microseconds, 1000)
    Mix.shell().info("\n--- transcript (#{elapsed_ms} ms wall time) ---\n#{text}\n--- end ---")
  end

  defp maybe_put(kw, _key, nil), do: kw
  defp maybe_put(kw, key, val), do: Keyword.put(kw, key, val)
end
