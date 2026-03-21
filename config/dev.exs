import Config

# Supervised GenServer (`NellyAssitant.Whisper.Mic.PipelineStarter`) starts the mic pipeline on boot.
# Do not run `mix nelly.mic` while this is true (two pipelines would contend for the mic).
config :nelly_assitant, :start_whisper_mic, true

# PortAudio + capture format (merged into `LivePipeline` / `mix nelly.mic_wav`).
# device_id: from `mix eval "Membrane.PortAudio.print_devices()"` (not the same number as ALSA card).
# Match a *working* arecord line: e.g. if `arecord -c 2 -r 44100` works, set channels: 2, sample_rate: 44100.
config :nelly_assitant, :voice_pipeline,
  device_id: 1,
  channels: 1,
  sample_format: :s16le,
  sample_rate: nil

# whisper_toilet_capacity: 100_000

if File.exists?("config/dev.local.exs") do
  import_config "dev.local.exs"
end
