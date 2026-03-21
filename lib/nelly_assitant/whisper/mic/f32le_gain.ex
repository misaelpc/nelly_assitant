defmodule NellyAssitant.Whisper.Mic.F32leGain do
  @moduledoc false
  use Membrane.Filter

  alias Membrane.{Buffer, RawAudio}

  def_input_pad :input,
    accepted_format: %RawAudio{sample_format: :f32le, channels: 1, sample_rate: 16_000}

  def_output_pad :output,
    accepted_format: %RawAudio{sample_format: :f32le, channels: 1, sample_rate: 16_000}

  def_options multiplier: [
                spec: float(),
                default: 1.0,
                description:
                  "Linear gain per sample after resample (e.g. 2.0 ≈ +6 dB). Values are clamped to [-1.0, 1.0]."
              ]

  @impl true
  def handle_init(_ctx, %__MODULE__{} = opts) do
    mult = opts.multiplier * 1.0
    {[], %{multiplier: mult}}
  end

  @impl true
  def handle_buffer(:input, buffer, _ctx, %{multiplier: mult} = state) do
    out =
      if mult == 1.0 do
        buffer
      else
        %Buffer{buffer | payload: scale_f32le(buffer.payload, mult)}
      end

    {[buffer: {:output, out}], state}
  end

  defp scale_f32le(payload, mult) do
    for <<f::float-little-32 <- payload>>, into: <<>> do
      x = f * mult
      x = max(-1.0, min(1.0, x))
      <<x::float-little-32>>
    end
  end
end
