import Config

config :nx, default_backend: EXLA.Backend

config :nelly_assitant, :start_whisper_mic, false

config :logger, level: :info

import_config "#{config_env()}.exs"
