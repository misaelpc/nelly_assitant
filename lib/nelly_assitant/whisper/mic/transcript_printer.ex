defmodule NellyAssitant.Whisper.Mic.TranscriptPrinter do
  @moduledoc false
  use Membrane.Filter

  def_input_pad(:input,
    accepted_format: _any
  )

  def_output_pad(:output,
    accepted_format: _any
  )

  @impl true
  def handle_buffer(:input, buffer, _ctx, state), do: {[forward: buffer], state}

  @impl true
  def handle_event(:input, %Membrane.Whisper.TranscriptEvent{text: text}, _ctx, state) do
    IO.puts(text)
    {[], state}
  end
end
