defmodule NellyAssitant.Whisper.Mic.LivePipeline do
  @moduledoc false
  use Membrane.Pipeline

  alias Membrane.RawAudio

  @whisper_audio %RawAudio{sample_format: :f32le, channels: 1, sample_rate: 16_000}

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
  def handle_init(_ctx, _opts) do
    device_id = Application.get_env(:nelly_assitant, :portaudio_input_device_id, :default)

    spec =
      child(:mic_source, %Membrane.PortAudio.Source{
        device_id: device_id,
        sample_format: :f32le,
        channels: 1,
        sample_rate: nil,
        latency: :low
      })
      |> child(:resample, %Membrane.FFmpeg.SWResample.Converter{
        output_stream_format: @whisper_audio
      })
      |> via_in(:input, toilet_capacity: 1_000)
      |> child(:whisper, %Membrane.Whisper.TranscriberFilter{
        serving: setup_serving()
      })
      |> child(:transcript_printer, NellyAssitant.Whisper.Mic.TranscriptPrinter)
      |> child(:sink, Membrane.Fake.Sink)

    {[spec: spec], %{}}
  end
end
