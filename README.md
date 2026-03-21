# NellyAssitant

Elixir app with a **live microphone → Whisper** Membrane pipeline (via [`membrane_whisper_plugin`](https://hex.pm/packages/membrane_whisper_plugin)).

## System requirements

- **PortAudio** — required by `membrane_portaudio_plugin` to capture the mic.  
  - macOS (Homebrew): `brew install portaudio`
- **FFmpeg** (libs + headers for compile) — required by `membrane_ffmpeg_swresample_plugin` to resample mic audio (native rate, e.g. 48 kHz) to **16 kHz** for Whisper.  
  - macOS: `brew install ffmpeg`  
  - Debian / Raspberry Pi OS: e.g. `sudo apt install ffmpeg libavcodec-dev libavformat-dev libavutil-dev libswresample-dev pkg-config`
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

### Check the microphone (WAV file, no Whisper / EXLA)

With **`start_whisper_mic` set to `false`** (so nothing else holds the mic):

```bash
mix nelly.mic_wav
# or: mix nelly.mic_wav --seconds 5 --output /tmp/mic_test.wav
```

This uses the same `:voice_pipeline` PortAudio settings and writes a playable WAV. On Linux: `aplay /tmp/mic_test.wav` (or `ffplay`). The pipeline stops **gracefully** so the WAV header and data finalize.

`mix test` keeps `:start_whisper_mic` false so CI does not open the microphone.

**Mic / PortAudio** — use a **single** `config :nelly_assitant, :voice_pipeline, ...` block (a second `config` for the same key **replaces** the whole map). Set **`device_id`** from `mix eval "Membrane.PortAudio.print_devices()"` (PortAudio indices ≠ ALSA `card` numbers).

**Raspberry Pi (USB mic):** If ALSA works, e.g. `arecord -D hw:2,0 -f S16_LE -c 2 -r 44100`, mirror that in Elixir: **`channels: 2`**, **`sample_rate: 44_100`**, **`sample_format: :s16le`**, and the **`device_id`** for your USB line. Opening **mono** (`channels: 1`) on a **stereo-only** path often gives **silence** even though `arecord -c 2` works.

Optional: copy [`config/dev.local.exs.example`](config/dev.local.exs.example) to **`config/dev.local.exs`** (gitignored); `dev.exs` imports it when present so you can keep Mac settings in `dev.exs` and Pi overrides locally.

Other options: optional `whisper_toilet_capacity` (default `50_000`; do not set to `nil`). After config changes, run **`mix compile`**. Legacy `portaudio_input_device_id` applies when `device_id` is absent.

## Installation (library)

If published to Hex, add to `mix.exs`:

```elixir
def deps do
  [
    {:nelly_assitant, "~> 0.1.0"}
  ]
end
```
