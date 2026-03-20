defmodule NellyAssitant.Application do
  @moduledoc false
  use Application

  @impl true
  def start(_type, _args) do
    children =
      if Application.get_env(:nelly_assitant, :start_whisper_mic, false) do
        [NellyAssitant.Whisper.Mic.PipelineStarter]
      else
        []
      end

    opts = [strategy: :one_for_one, name: NellyAssitant.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
