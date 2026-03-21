defmodule NellyAssitant.MicToWavPipelineTest do
  use ExUnit.Case

  test "MicToWavPipeline is available — run `mix nelly.mic_wav` to record raw PCM from the mic" do
    assert Code.ensure_loaded?(NellyAssitant.Whisper.Mic.MicToWavPipeline)
  end
end
