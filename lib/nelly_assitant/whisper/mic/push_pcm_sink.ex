defmodule NellyAssitant.Whisper.Mic.PushPcmSink do
  @moduledoc false
  use Membrane.Sink

  alias Membrane.RawAudio

  def_input_pad :input,
    flow_control: :push,
    accepted_format: RawAudio

  def_options location: [
                spec: Path.t(),
                description: "Output path; raw little-endian PCM (no WAV header)."
              ]

  @impl true
  def handle_init(_ctx, %__MODULE__{location: location}) do
    {[], %{path: Path.expand(location), fd: nil, bytes: 0}}
  end

  @impl true
  def handle_setup(ctx, %{path: path} = state) do
    path |> Path.dirname() |> File.mkdir_p!()
    _ = File.rm(path)
    fd = File.open!(path, [:write, :binary])

    Membrane.ResourceGuard.register(ctx.resource_guard, fn -> File.close(fd) end)

    {[], %{state | fd: fd}}
  end

  @impl true
  def handle_stream_format(:input, format, _ctx, state) do
    Membrane.Logger.info(
      "PushPcmSink capturing #{inspect(format.sample_format)} #{format.channels}ch @ #{format.sample_rate} Hz -> #{state.path}"
    )

    {[], state}
  end

  @impl true
  def handle_buffer(:input, buffer, _ctx, state) do
    :ok = IO.binwrite(state.fd, buffer.payload)
    {[], %{state | bytes: state.bytes + byte_size(buffer.payload)}}
  end

  @impl true
  def handle_end_of_stream(:input, _ctx, state) do
    Membrane.Logger.info("PushPcmSink finished: #{state.bytes} bytes -> #{state.path}")
    {[], state}
  end
end
