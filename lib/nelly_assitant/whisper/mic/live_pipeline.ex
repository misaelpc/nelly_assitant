defmodule NellyAssitant.Whisper.Mic.LivePipeline do
  @moduledoc """
  Membrane pipeline: microphone → FFmpeg resample (16 kHz mono `f32le`) → Whisper → transcript sink.

  Options are merged from `Application.get_env(:nelly_assitant, :voice_pipeline, [])` and the second
  argument to `Membrane.Pipeline.start_link/2` (later keys win), similar to passing opts into a
  custom `handle_init/2` pipeline module.

  * `:channels` — omit to use the **PortAudio device default**. If ALSA needs **`-c 2`** for your mic
    (e.g. `arecord ... -c 2 -r 44100` works), set **`channels: 2`** here; **mono (`1`) can be silent**
    on some stereo USB gadgets.

  * `:whisper_toilet_capacity` — queue size for **both** toilets (mic → resampler and resampler →
    Whisper; default `50_000`). The mic → resampler link used to use Membrane’s implicit default
    (~`1000`) unless this is set on an explicit `via_in`. Do not set this key to `nil` if you mean
    “default”; omit the key instead.

  * `:mic_f32_gain` — optional linear gain on **16 kHz mono float** audio **after** resample and
    **before** Whisper (default `1.0`). Use e.g. `2.0` or `3.0` if the mic is quiet; samples are
    clamped to `[-1.0, 1.0]` to limit clipping.

  * `:whisper_hf_repo` — Hugging Face repo id (default `"openai/whisper-tiny"`). **`whisper-base`**
    or **`whisper-small`** are much more accurate but slower and heavier (RAM / first compile).

  * `:whisper_chunk_seconds` — streaming chunk length in seconds (default `6`). **Very small values**
    (e.g. `2`) cause more boundary merges and garbled / repeated phrases; **larger** values improve
    phrasing at the cost of latency before each transcript line.

  * `:whisper_context_seconds` — optional overlap context passed to Bumblebee (default: chunk / 6).
    Only set if you know you need a different overlap; must satisfy
    `chunk_num_seconds > 2 * context_num_seconds`.

  * `:whisper_language` — BCP-47 style code for multilingual models (default `"en"`). Set to `nil`
    to let the model detect language (slightly different behavior / cost).
  """

  use Membrane.Pipeline

  alias Membrane.RawAudio

  @whisper_audio %RawAudio{sample_format: :f32le, channels: 1, sample_rate: 16_000}

  @default_whisper_toilet_capacity 50_000
  @default_whisper_hf_repo "openai/whisper-tiny"
  @default_whisper_chunk_seconds 6

  defp setup_serving(merged_opts) do
    hf_repo = Keyword.get(merged_opts, :whisper_hf_repo, @default_whisper_hf_repo)
    chunk_sec = resolve_whisper_chunk_seconds(merged_opts)

    whisper_opts =
      [
        stream: true,
        chunk_num_seconds: chunk_sec,
        language: resolve_whisper_language(merged_opts)
      ]
      |> maybe_put_whisper_context(merged_opts)

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

  @impl true
  def handle_init(_ctx, opts) when is_list(opts) do
    merged =
      :nelly_assitant
      |> Application.get_env(:voice_pipeline, [])
      |> Keyword.merge(opts)

    source_opts = build_mic_source_opts(merged)

    toilet_capacity = resolve_toilet_capacity(merged)
    f32_gain = resolve_f32_gain(merged)

    after_resample =
      child(:mic_source, struct(Membrane.PortAudio.Source, source_opts))
      |> via_in(:input, toilet_capacity: toilet_capacity)
      |> child(:resample, %Membrane.FFmpeg.SWResample.Converter{
        output_stream_format: @whisper_audio
      })

    to_whisper =
      if f32_gain == 1.0 do
        after_resample
      else
        after_resample
        |> child(:mic_gain, %NellyAssitant.Whisper.Mic.F32leGain{multiplier: f32_gain})
      end

    spec =
      to_whisper
      |> via_in(:input, toilet_capacity: toilet_capacity)
      |> child(:whisper, %Membrane.Whisper.TranscriberFilter{
        serving: setup_serving(merged)
      })
      |> child(:transcript_printer, NellyAssitant.Whisper.Mic.TranscriptPrinter)
      |> child(:sink, Membrane.Fake.Sink)

    {[spec: spec], %{}}
  end

  defp build_mic_source_opts(opts) do
    device_id =
      case Keyword.fetch(opts, :device_id) do
        {:ok, id} -> id
        :error -> Application.get_env(:nelly_assitant, :portaudio_input_device_id, :default)
      end

    base = [
      device_id: device_id,
      sample_format: Keyword.get(opts, :sample_format, :s16le),
      latency: Keyword.get(opts, :latency, :low)
    ]

    base =
      case Keyword.fetch(opts, :channels) do
        {:ok, c} -> Keyword.put(base, :channels, c)
        :error -> base
      end

    case Keyword.fetch(opts, :sample_rate) do
      {:ok, rate} -> Keyword.put(base, :sample_rate, rate)
      :error -> base
    end
  end

  defp resolve_toilet_capacity(opts) do
    case Keyword.fetch(opts, :whisper_toilet_capacity) do
      {:ok, n} when is_integer(n) and n > 0 -> n
      {:ok, _} -> @default_whisper_toilet_capacity
      :error -> @default_whisper_toilet_capacity
    end
  end

  defp resolve_f32_gain(opts) do
    case Keyword.fetch(opts, :mic_f32_gain) do
      {:ok, n} when is_number(n) and n > 0 -> n * 1.0
      {:ok, _} -> 1.0
      :error -> 1.0
    end
  end

  defp resolve_whisper_chunk_seconds(opts) do
    case Keyword.fetch(opts, :whisper_chunk_seconds) do
      {:ok, n} when is_number(n) and n > 0 -> n * 1.0
      {:ok, _} -> @default_whisper_chunk_seconds * 1.0
      :error -> @default_whisper_chunk_seconds * 1.0
    end
  end

  defp resolve_whisper_language(opts) do
    case Keyword.fetch(opts, :whisper_language) do
      {:ok, nil} -> nil
      {:ok, lang} when is_binary(lang) -> lang
      {:ok, _} -> "en"
      :error -> "en"
    end
  end

  defp maybe_put_whisper_context(opts, merged) do
    case Keyword.fetch(merged, :whisper_context_seconds) do
      {:ok, n} when is_number(n) and n > 0 ->
        Keyword.put(opts, :context_num_seconds, n * 1.0)

      _ ->
        opts
    end
  end
end
