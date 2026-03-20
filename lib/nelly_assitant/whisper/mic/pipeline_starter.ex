defmodule NellyAssitant.Whisper.Mic.PipelineStarter do
  @moduledoc """
  Starts `NellyAssitant.Whisper.Mic.LivePipeline` under the application supervisor when
  `:start_whisper_mic` is enabled in config (see `config/dev.exs`). Use this instead of
  `mix nelly.mic` when you want the mic to come up automatically with `iex -S mix` / `mix run`.
  """
  use GenServer

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def child_spec(opts) do
    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, [opts]}
    }
  end

  @impl true
  def init(_opts) do
    case Membrane.Pipeline.start_link(NellyAssitant.Whisper.Mic.LivePipeline, []) do
      {:ok, _supervisor, pipeline} ->
        {:ok, %{pipeline: pipeline}}

      {:error, reason} ->
        {:stop, reason}
    end
  end

  @impl true
  def terminate(_reason, %{pipeline: pipeline}) do
    Membrane.Pipeline.terminate(pipeline, timeout: 15_000, force?: true)
    :ok
  end

  @impl true
  def terminate(_reason, _state), do: :ok
end
