require "prius"
require "hutch"
require "raven"
require "./lib/null_logger"

Prius.load(:bump_github_token)
Prius.load(:sentry_dsn, required: false)
Prius.load(:amqp_host)
Prius.load(:amqp_api_host)
Prius.load(:amqp_api_port)
Prius.load(:amqp_vhost)
Prius.load(:amqp_api_ssl, type: :bool)
Prius.load(:amqp_username)
Prius.load(:amqp_password)

Raven.configure do |config|
  config.dsn = Prius.get(:sentry_dsn) if Prius.get(:sentry_dsn)
  config.logger = NullLogger.new(STDOUT) unless Prius.get(:sentry_dsn)
end

Hutch::Config.set(:mq_host, Prius.get(:amqp_host))
Hutch::Config.set(:mq_api_host, Prius.get(:amqp_api_host))
Hutch::Config.set(:mq_api_port, Prius.get(:amqp_api_port))
Hutch::Config.set(:mq_vhost, Prius.get(:amqp_vhost))
Hutch::Config.set(:mq_api_ssl, Prius.get(:amqp_api_ssl))
Hutch::Config.set(:mq_username, Prius.get(:amqp_username))
Hutch::Config.set(:mq_password, Prius.get(:amqp_password))
