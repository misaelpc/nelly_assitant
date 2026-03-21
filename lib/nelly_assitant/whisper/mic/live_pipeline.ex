defmodule NellyAssitant.Whisper.Mic.LivePipeline do
  @moduledoc """
  Membrane pipeline: microphone → FFmpeg resample (16 kHz mono `f32le`) → Whisper → transcript sink.

  Options are merged from `Application.get_env(:nelly_assitant, :voice_pipeline, [])` and the second
  argument to `Membrane.Pipeline.start_link/2` (later keys win), similar to passing opts into a
  custom `handle_init/2` pipeline module.

  * `:channels` — omit to use the **PortAudio device default**. If ALSA needs **`-c 2`** for your mic
    (e.g. `arecord ... -c 2 -r 44100` works), set **`channels: 2`** here; **mono (`1`) can be silent**
    on some stereo USB gadgets.

  * `:whisper_toilet_capacity` — **legacy:** toilet size for **mic → resample** only (default
    `50_000`). Keep this **high** so push audio does not overflow.

  * `:mic_resample_toilet_capacity` — overrides the mic → resample toilet when set (otherwise
    `whisper_toilet_capacity` or default `50_000`).

  * `:whisper_input_toilet_capacity` — toilet **before Whisper** (default **`32_000`** buffers).
    Must be large enough that **push** audio from the resampler does not overflow while Whisper
    runs; **`4_000` is too small** for typical live capture. Lower values reduce worst‑case lag if
    inference keeps up with realtime.

  * `:whisper_disable_compile` — if `true`, skip Bumblebee `compile: [batch_size: …]` (default is
    compiled with `whisper_compile_batch_size`, default `1`, for faster steady‑state inference).

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

  * `:whisper_file_chunk_seconds` — used only by **`mix nelly.whisper_file`** (default `30`) for
    long files; live mic uses **`whisper_chunk_seconds`** instead.
  """

  use Membrane.Pipeline

  alias Membrane.RawAudio

  @whisper_audio %RawAudio{sample_format: :f32le, channels: 1, sample_rate: 16_000}

  @default_mic_resample_toilet_capacity 50_000
  @default_whisper_input_toilet_capacity 32_000

  @impl true
  def handle_init(_ctx, opts) when is_list(opts) do
    merged =
      :nelly_assitant
      |> Application.get_env(:voice_pipeline, [])
      |> Keyword.merge(opts)

    source_opts = build_mic_source_opts(merged)

    {mic_toilet, whisper_toilet} = resolve_toilet_capacities(merged)
    f32_gain = resolve_f32_gain(merged)

    after_resample =
      child(:mic_source, struct(Membrane.PortAudio.Source, source_opts))
      |> via_in(:input, toilet_capacity: mic_toilet)
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
      |> via_in(:input, toilet_capacity: whisper_toilet)
      |> child(:whisper, %Membrane.Whisper.TranscriberFilter{
        serving: NellyAssitant.Whisper.WhisperServing.build_for_live(merged)
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

  defp resolve_toilet_capacities(opts) do
    mic =
      case Keyword.fetch(opts, :mic_resample_toilet_capacity) do
        {:ok, n} when is_integer(n) and n > 0 ->
          n

        _ ->
          case Keyword.fetch(opts, :whisper_toilet_capacity) do
            {:ok, n} when is_integer(n) and n > 0 -> n
            {:ok, _} -> @default_mic_resample_toilet_capacity
            :error -> @default_mic_resample_toilet_capacity
          end
      end

    whisper =
      case Keyword.fetch(opts, :whisper_input_toilet_capacity) do
        {:ok, n} when is_integer(n) and n > 0 -> n
        {:ok, _} -> @default_whisper_input_toilet_capacity
        :error -> @default_whisper_input_toilet_capacity
      end

    {mic, whisper}
  end

  defp resolve_f32_gain(opts) do
    case Keyword.fetch(opts, :mic_f32_gain) do
      {:ok, n} when is_number(n) and n > 0 -> n * 1.0
      {:ok, _} -> 1.0
      :error -> 1.0
    end
  end
end
