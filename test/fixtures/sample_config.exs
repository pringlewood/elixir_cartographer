import Config

config :sample_app, SampleAppWeb.Endpoint,
  url: [host: "localhost"],
  secret_key_base: "abc123"

config :sample_app, SampleApp.Repo,
  username: System.get_env("DATABASE_USER", "postgres"),
  password: System.get_env("DATABASE_PASSWORD"),
  database: System.get_env("DATABASE_NAME", "sample_app_dev"),
  hostname: System.get_env("DATABASE_HOST", "localhost"),
  pool_size: 10

config :sample_app, :feature_flags,
  enable_beta: true,
  enable_dark_mode: false

config :sample_app, SampleApp.Mailer,
  adapter: Swoosh.Adapters.SMTP,
  relay: System.get_env("SMTP_HOST")
