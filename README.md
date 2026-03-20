# NellyAssitant

Elixir app with a **live microphone → Whisper** Membrane pipeline (via [`membrane_whisper_plugin`](https://hex.pm/packages/membrane_whisper_plugin)).

## System requirements

- **PortAudio** — required by `membrane_portaudio_plugin` to capture the mic.  
  - macOS (Homebrew): `brew install portaudio`
- **EXLA / XLA** — Whisper inference uses the EXLA backend. Follow the [EXLA installation guide](https://hexdocs.pm/exla) for your OS (CPU vs GPU). First compile may download or build native artifacts.  
  - If unpacking fails with `:eof`, remove the partial cache and recompile, e.g. `mix deps.clean exla --build` and `mix deps.compile exla`.
- **Network** — the first run downloads the `openai/whisper-tiny` weights from Hugging Face.

## Run the live mic demo

Use **one** of these (not both — they would both try to use the microphone):

1. **Automatic start in dev (default)** — `config/dev.exs` sets `:start_whisper_mic` to `true`, so a supervised `NellyAssitant.Whisper.Mic.PipelineStarter` GenServer starts the pipeline when you run `iex -S mix` or `mix run --no-halt`. Transcripts print to the terminal from `TranscriptEvent`s. Set it to `false` in `config/dev.exs` if you want the app up without using the mic.

2. **Mix task** — when `:start_whisper_mic` is `false` (e.g. base `config` or you disabled dev), run:

   ```bash
   mix nelly.mic
   ```

`mix test` keeps `:start_whisper_mic` false so CI does not open the microphone.

**Input device** — dev sets `:portaudio_input_device_id` (see `config/dev.exs`). Use `mix pa_devices` to list ids on your machine; omit or set `:default` for the OS default input.

## Installation (library)

If published to Hex, add to `mix.exs`:

```elixir
def deps do
  [
    {:nelly_assitant, "~> 0.1.0"}
  ]
end
```
