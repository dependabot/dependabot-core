import Config

config :dependabot,
  port: String.to_integer(System.get_env("PORT", "8000")),
  auth_token: System.get_env("AUTH_TOKEN", "d6fc2b6n6h7katic6vuq6k5e2csahcm4")
