import Config

# Supervised GenServer (`NellyAssitant.Whisper.Mic.PipelineStarter`) starts the mic pipeline on boot.
# Do not run `mix nelly.mic` while this is true (two pipelines would contend for the mic).
config :nelly_assitant, :start_whisper_mic, true

# PortAudio + capture format (merged into `LivePipeline`; see moduledoc).
# Use `mix eval "Membrane.PortAudio.print_devices()"` for `device_id` on each machine.
# Omit `:sample_rate` to let the device pick its native rate (resampler feeds Whisper at 16 kHz).
config :nelly_assitant, :voice_pipeline,
  device_id: 1,
  # On Raspberry Pi + stereo USB mic: omit `:channels` so PortAudio uses the device default (forcing `1` can record silence).
  channels: 1,
  sample_format: :s16le,
  sample_rate: nil

# whisper_toilet_capacity: 100_000
