defmodule NellyAssitant.Whisper.WhisperServing do
  @moduledoc false

  @default_hf_repo "openai/whisper-tiny"
  @default_live_chunk_seconds 6
  @default_file_chunk_seconds 30

  @doc "Serving for `Membrane.Whisper.TranscriberFilter` (streaming enumerable audio)."
  def build_for_live(merged_opts) when is_list(merged_opts) do
    hf_repo = Keyword.get(merged_opts, :whisper_hf_repo, @default_hf_repo)
    chunk_sec = resolve_live_chunk_seconds(merged_opts)

    whisper_opts =
      [
        stream: true,
        chunk_num_seconds: chunk_sec,
        language: resolve_language(merged_opts)
      ]
      |> maybe_put_context(merged_opts)
      |> maybe_put_compile(merged_opts)

    build(hf_repo, whisper_opts)
  end

  @doc """
  Non-streaming serving for `Nx.Serving.run(serving, {:file, path})`.
  Uses ffmpeg (via Bumblebee) to decode WAV/MP3/etc. to the model rate.
  """
  def build_for_file(merged_opts) when is_list(merged_opts) do
    hf_repo = Keyword.get(merged_opts, :whisper_hf_repo, @default_hf_repo)

    chunk_sec =
      case Keyword.fetch(merged_opts, :whisper_file_chunk_seconds) do
        {:ok, n} when is_number(n) and n > 0 -> n * 1.0
        {:ok, _} -> @default_file_chunk_seconds * 1.0
        :error -> @default_file_chunk_seconds * 1.0
      end

    whisper_opts =
      [
        stream: false,
        chunk_num_seconds: chunk_sec,
        language: resolve_language(merged_opts)
      ]
      |> maybe_put_context(merged_opts)
      |> maybe_put_compile(merged_opts)

    build(hf_repo, whisper_opts)
  end

  defp build(hf_repo, whisper_opts) do
    {:ok, whisper} = Bumblebee.load_model({:hf, hf_repo})
    {:ok, featurizer} = Bumblebee.load_featurizer({:hf, hf_repo})
    {:ok, tokenizer} = Bumblebee.load_tokenizer({:hf, hf_repo})
    {:ok, generation_config} = Bumblebee.load_generation_config({:hf, hf_repo})

    Bumblebee.Audio.speech_to_text_whisper(
      whisper,
      featurizer,
      tokenizer,
      generation_config,
      whisper_opts
    )
  end

  defp resolve_live_chunk_seconds(opts) do
    case Keyword.fetch(opts, :whisper_chunk_seconds) do
      {:ok, n} when is_number(n) and n > 0 -> n * 1.0
      {:ok, _} -> @default_live_chunk_seconds * 1.0
      :error -> @default_live_chunk_seconds * 1.0
    end
  end

  defp resolve_language(opts) do
    case Keyword.fetch(opts, :whisper_language) do
      {:ok, nil} -> nil
      {:ok, lang} when is_binary(lang) -> lang
      {:ok, _} -> "en"
      :error -> "en"
    end
  end

  defp maybe_put_context(opts, merged) do
    case Keyword.fetch(merged, :whisper_context_seconds) do
      {:ok, n} when is_number(n) and n > 0 ->
        Keyword.put(opts, :context_num_seconds, n * 1.0)

      _ ->
        opts
    end
  end

  defp maybe_put_compile(opts, merged) do
    if Keyword.get(merged, :whisper_disable_compile, false) do
      opts
    else
      batch =
        case Keyword.fetch(merged, :whisper_compile_batch_size) do
          {:ok, n} when is_integer(n) and n > 0 -> n
          _ -> 1
        end

      Keyword.put(opts, :compile, [batch_size: batch])
    end
  end
end
