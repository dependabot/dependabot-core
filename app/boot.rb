require "prius"
require "sidekiq"
require "raven"
require "./lib/null_logger"

Prius.load(:bump_github_token)
Prius.load(:sentry_dsn, required: false)

Raven.configure do |config|
  config.dsn = Prius.get(:sentry_dsn) if Prius.get(:sentry_dsn)
  config.logger = NullLogger.new(STDOUT) unless Prius.get(:sentry_dsn)
end
