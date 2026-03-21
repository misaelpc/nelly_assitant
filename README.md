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
- **Network** — the first run downloads Whisper weights from Hugging Face (default repo `openai/whisper-tiny`; you can switch to `openai/whisper-base` in config — see below).

## Run the live mic demo

Use **one** of these (not both — they would both try to use the microphone):

1. **Automatic start in dev (default)** — `config/dev.exs` sets `:start_whisper_mic` to `true`, so a supervised `NellyAssitant.Whisper.Mic.PipelineStarter` GenServer starts the pipeline when you run `iex -S mix` or `mix run --no-halt`. Transcripts print to the terminal from `TranscriptEvent`s. Set it to `false` in `config/dev.exs` if you want the app up without using the mic.

2. **Mix task** — when `:start_whisper_mic` is `false` (e.g. base `config` or you disabled dev), run:

   ```bash
   mix nelly.mic
   ```

### Transcription quality (missing words, scrambled phrases)

The defaults favor a **small, fast** model (`openai/whisper-tiny`) and **6 s** streaming chunks (Bumblebee merges overlaps between chunks). If you see lots of dropped words or nonsense like split “one two three” across lines:

1. **Use a larger model** — in `:voice_pipeline` set **`whisper_hf_repo: "openai/whisper-base"`** (or `whisper-small` if you have RAM). First run downloads and compiles a bigger graph; accuracy improves a lot.
2. **Keep chunks reasonably long** — **`whisper_chunk_seconds`** defaults to **6**. Values like **2** update the screen faster but worsen boundary artifacts; try **8–10** if you can tolerate slower subtitles.
3. **Level and language** — ensure **`mic_f32_gain`** and capture volume are adequate; **`whisper_language: "en"`** (default) matches English speech (set **`whisper_language: nil`** only if you want automatic language detection on a multilingual checkpoint).

### Latency & toilet overflow (live mic)

The resampler **pushes** buffers into a Membrane **toilet** in front of Whisper. If that toilet is **too small**, you get **`Toilet overflow`** even when CPU usage looks moderate — it means **Whisper is consuming buffers slower than capture produces them**, so the queue hits its cap.

- **`whisper_input_toilet_capacity`** defaults to **`32_000`** buffers so live capture does not trip overflow as easily as with **`4_000`**. If you **lower** it to reduce worst-case lag, increase gradually if overflows return.
- **`whisper_toilet_capacity` / `mic_resample_toilet_capacity`** (default **`50_000`**) stay on the **mic → resample** link only.
- Prefer **`openai/whisper-tiny`** on a Pi; **`whisper-base`** is slower per chunk.
- Bumblebee **`compile: [batch_size: 1]`** is on by default; **`whisper_disable_compile: true`** only for debugging.

### Benchmark Whisper on a file (no mic)

To check **pure inference** time on the Pi (ffmpeg decode + EXLA), disable **`start_whisper_mic`**, then:

```bash
mix nelly.whisper_file /tmp/mic_capture.wav
# mix nelly.whisper_file clip.mp3 --repo openai/whisper-base --chunk-seconds 30
```

Uses the same `:voice_pipeline` repo / language / compile flags where applicable. Prints **wall time in ms** and the full transcript.

**Speech vs music:** Whisper targets **spoken** audio. **Songs with full instrumentation** (e.g. jazz, pop mixes) often produce **garbled or repetitive** text (“music”, “thank you”, fragments)—that is normal, not a broken install. Use a **spoken** clip or **isolated vocals** to judge model quality.

### Check the microphone (raw PCM, no Whisper / EXLA)

With **`start_whisper_mic` set to `false`** (so nothing else holds the mic):

```bash
mix nelly.mic_wav
# or: mix nelly.mic_wav --seconds 5 --output /tmp/mic_test.raw
```

This uses the same `:voice_pipeline` PortAudio settings and writes **raw little-endian PCM** (no WAV header), using a **push** sink so capture is not stalled by the WAV / manual-demand chain. Convert to WAV with `ffmpeg`, matching your config (example for stereo 44.1 kHz s16le):

```bash
ffmpeg -f s16le -ar 44100 -ac 2 -i mic_capture.raw mic_capture.wav
```

**Playback sounds quiet?** Boost at convert time, e.g. about **+10 dB** (`volume=3.16` is ~10 dB; tune to taste):

```bash
ffmpeg -f s16le -ar 44100 -ac 2 -i mic_capture.raw -af volume=3 mic_louder.wav
```

Or raise **capture** level on Linux: `alsamixer` → **F4** (Capture) → increase Mic / USB gain.

For the **live Whisper** pipeline, optional software gain **after resample** (before the model): in `:voice_pipeline` set **`mic_f32_gain`** (linear, default `1.0`), e.g. `2.0` or `3.0`. Samples are clamped to `[-1, 1]`.

The pipeline stops **gracefully**; check logs for `PushPcmSink finished: <N> bytes`.

`mix test` keeps `:start_whisper_mic` false so CI does not open the microphone.

**Mic / PortAudio** — use a **single** `config :nelly_assitant, :voice_pipeline, ...` block (a second `config` for the same key **replaces** the whole map). Set **`device_id`** from `mix eval "Membrane.PortAudio.print_devices()"` (PortAudio indices ≠ ALSA `card` numbers).

**Raspberry Pi (USB mic):** If ALSA works, e.g. `arecord -D hw:2,0 -f S16_LE -c 2 -r 44100`, mirror that in Elixir: **`channels: 2`**, **`sample_rate: 44_100`**, **`sample_format: :s16le`**, and the **`device_id`** for your USB line. Opening **mono** (`channels: 1`) on a **stereo-only** path often gives **silence** even though `arecord -c 2` works.

Optional: copy [`config/dev.local.exs.example`](config/dev.local.exs.example) to **`config/dev.local.exs`** (gitignored); `dev.exs` imports it when present so you can keep Mac settings in `dev.exs` and Pi overrides locally.

Other options: **`whisper_toilet_capacity`** / **`mic_resample_toilet_capacity`** (mic → resample, default `50_000`); **`whisper_input_toilet_capacity`** (before Whisper, default `32_000`). After config changes, run **`mix compile`**. Legacy `portaudio_input_device_id` applies when `device_id` is absent.

## Installation (library)

If published to Hex, add to `mix.exs`:

```elixir
def deps do
  [
    {:nelly_assitant, "~> 0.1.0"}
  ]
end
```
