import Config

# Supervised GenServer (`NellyAssitant.Whisper.Mic.PipelineStarter`) starts the mic pipeline on boot.
# Do not run `mix nelly.mic` while this is true (two pipelines would contend for the mic).
config :nelly_assitant, :start_whisper_mic, true

# PortAudio input device id (`mix pa_devices`). 1 = "misa's AirPods Pro Apple" (mic) on this machine.
config :nelly_assitant, :portaudio_input_device_id, 1
