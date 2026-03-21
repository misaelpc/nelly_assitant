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
  """

  use Membrane.Pipeline

  alias Membrane.RawAudio

  @whisper_audio %RawAudio{sample_format: :f32le, channels: 1, sample_rate: 16_000}

  @default_whisper_toilet_capacity 50_000

  defp setup_serving do
    hf_repo = "openai/whisper-tiny"

    {:ok, whisper} = Bumblebee.load_model({:hf, hf_repo})
    {:ok, featurizer} = Bumblebee.load_featurizer({:hf, hf_repo})
    {:ok, tokenizer} = Bumblebee.load_tokenizer({:hf, hf_repo})
    {:ok, generation_config} = Bumblebee.load_generation_config({:hf, hf_repo})

    Bumblebee.Audio.speech_to_text_whisper(
      whisper,
      featurizer,
      tokenizer,
      generation_config,
      stream: true,
      chunk_num_seconds: 2,
      language: "en"
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

    spec =
      child(:mic_source, struct(Membrane.PortAudio.Source, source_opts))
      |> via_in(:input, toilet_capacity: toilet_capacity)
      |> child(:resample, %Membrane.FFmpeg.SWResample.Converter{
        output_stream_format: @whisper_audio
      })
      |> via_in(:input, toilet_capacity: toilet_capacity)
      |> child(:whisper, %Membrane.Whisper.TranscriberFilter{
        serving: setup_serving()
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
end
