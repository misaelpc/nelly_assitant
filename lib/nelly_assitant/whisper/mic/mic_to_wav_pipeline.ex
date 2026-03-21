defmodule NellyAssitant.Whisper.Mic.MicToWavPipeline do
  @moduledoc """
  Records from `Membrane.PortAudio.Source` to a WAV file using the same `:voice_pipeline` options
  as `NellyAssitant.Whisper.Mic.LivePipeline` (device, channels, sample format, sample rate).

  Use `mix nelly.mic_wav` to verify capture without loading Whisper/EXLA.

  Match a known-good **`arecord`** line: if you use **`-c 2 -r 44100`**, set **`channels: 2`** and
  **`sample_rate: 44_100`** in `:voice_pipeline` (mono can be silent on some stereo USB mics).
  """

  use Membrane.Pipeline

  @default_toilet_capacity 50_000
  @record_timer :mic_wav_record

  @impl true
  def handle_init(_ctx, opts) when is_list(opts) do
    output =
      case Keyword.fetch(opts, :output) do
        {:ok, path} when is_binary(path) -> Path.expand(path)
        _ -> raise ArgumentError, "required option :output — path to .wav file"
      end

    record_seconds = Keyword.get(opts, :record_seconds, 3)

    merged =
      :nelly_assitant
      |> Application.get_env(:voice_pipeline, [])
      |> Keyword.merge(Keyword.drop(opts, [:output, :record_seconds]))

    source_opts = mic_source_keyword(merged)
    toilet = toilet_capacity(merged)

    spec =
      child(:mic_source, struct(Membrane.PortAudio.Source, source_opts))
      |> via_in(:input, toilet_capacity: toilet)
      |> child(:wav, Membrane.WAV.Serializer)
      |> via_in(:input, toilet_capacity: toilet)
      |> child(:sink, %Membrane.File.Sink{location: output})

    actions = [
      spec: spec,
      start_timer: {@record_timer, Membrane.Time.seconds(record_seconds)}
    ]

    {actions, %{}}
  end

  @impl true
  def handle_tick(timer_id, _ctx, state) when timer_id == @record_timer do
    {[
       stop_timer: @record_timer,
       terminate: :normal
     ], state}
  end

  defp mic_source_keyword(opts) do
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

  defp toilet_capacity(opts) do
    case Keyword.fetch(opts, :whisper_toilet_capacity) do
      {:ok, n} when is_integer(n) and n > 0 -> n
      {:ok, _} -> @default_toilet_capacity
      :error -> @default_toilet_capacity
    end
  end
end
