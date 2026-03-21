defmodule NellyAssitant.Whisper.Mic.MicToWavPipeline do
  @moduledoc """
  Records from `Membrane.PortAudio.Source` to **raw PCM** (no WAV header) using the same
  `:voice_pipeline` options as `NellyAssitant.Whisper.Mic.LivePipeline`.

  Uses **push** flow end-to-end (`PortAudio.Source` → `PushPcmSink`) so capture is not blocked by
  the WAV serializer / manual `File.Sink` demand chain (which could yield a silent file on some setups).

  Use `mix nelly.mic_wav` to verify capture without Whisper/EXLA. Convert to WAV with `ffmpeg`, e.g.:

      ffmpeg -f s16le -ar 44100 -ac 2 -i mic_capture.raw mic_capture.wav

  Match a known-good **`arecord`** line: if you use **`-c 2 -r 44100`**, set **`channels: 2`** and
  **`sample_rate: 44_100`** in `:voice_pipeline` (mono can be silent on some stereo USB mics).
  """

  use Membrane.Pipeline

  @record_timer :mic_wav_record

  @impl true
  def handle_init(_ctx, opts) when is_list(opts) do
    output =
      case Keyword.fetch(opts, :output) do
        {:ok, path} when is_binary(path) -> Path.expand(path)
        _ -> raise ArgumentError, "required option :output — path to raw PCM file"
      end

    record_seconds = Keyword.get(opts, :record_seconds, 3)

    merged =
      :nelly_assitant
      |> Application.get_env(:voice_pipeline, [])
      |> Keyword.merge(Keyword.drop(opts, [:output, :record_seconds]))

    source_opts = mic_source_keyword(merged)

    spec =
      child(:mic_source, struct(Membrane.PortAudio.Source, source_opts))
      |> child(:sink, %NellyAssitant.Whisper.Mic.PushPcmSink{location: output})

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
end
