# frozen_string_literal: true

require "dependabot/logger"
require "dependabot/logger/formats"
require "dependabot/environment"

Dependabot.logger = Logger.new($stdout).tap do |logger|
  logger.level = Dependabot::Environment.log_level
  logger.formatter = Dependabot::Logger::BasicFormatter.new
end

require "dependabot/sentry"
Sentry.init do |config|
  debugger
  # config.logger = Dependabot.logger # TODO
  config.project_root = File.expand_path("../../..", __dir__)

  # Send messages synchronously rather than async. The updater is already a background job; no human is waiting for a
  # low latency response. So sending synchronously reduces complexity and ensures a job doesn't fire an exception
  # then exit immediately before the thread pool has a chance to send the exception.
  config.background_worker_threads = 0

  config.app_dirs_pattern = %r{(
    dependabot-updater/bin|
    dependabot-updater/config|
    dependabot-updater/lib|
    common|
    python|
    terraform|
    elm|
    docker|
    git_submodules|
    github_actions|
    composer|
    nuget|
    gradle|
    maven|
    hex|
    cargo|
    go_modules|
    npm_and_yarn|
    bundler|
    pub
  )}x

  config.before_send = lambda do |event, hint|
    if hint[:exception]
      ExceptionSanitizer.sanitize_sentry_exception_event(event, hint)

      # TODO integrate our custom `raven_context` methods too... for example code see:
      # https://docs.sentry.io/platforms/ruby/migration/#exceptionraven_context
      # https://github.com/getsentry/sentry-ruby/issues/884
      # https://github.com/getsentry/sentry-ruby/issues/1239
      # https://github.com/getsentry/sentry-ruby/issues/803
      if exception = hint[:exception]
        exception.raven_context.each do |key, value|
          event.send("#{key}=", value)
        end
      end

    else
      event
    end
  end

  # https://docs.sentry.io/platforms/ruby/migration/#exceptionraven_context
  # sentry-ruby doesn't capture raven_context from exceptions anymore. However, you can use before_send to replicate the same behavior:
  # TODO: when renaming raven_context first see if it used to be auto-picked up and we now need to change it
end

# We configure `Dependabot::Utils.register_always_clone` for some ecosystems. In
# order for that configuration to take effect, we need to make sure that these
# registration commands have been executed.
require "dependabot/python"
require "dependabot/terraform"
require "dependabot/elm"
require "dependabot/docker"
require "dependabot/git_submodules"
require "dependabot/github_actions"
require "dependabot/composer"
require "dependabot/nuget"
require "dependabot/gradle"
require "dependabot/maven"
require "dependabot/hex"
require "dependabot/cargo"
require "dependabot/go_modules"
require "dependabot/npm_and_yarn"
require "dependabot/bundler"
require "dependabot/pub"
