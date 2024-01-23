# typed: strict
# frozen_string_literal: true

require "sentry-ruby"

require "dependabot/environment"
require "dependabot/logger"
require "dependabot/logger/formats"
require "dependabot/sentry/processor"

Dependabot.logger = Logger.new($stdout).tap do |logger|
  logger.level = Dependabot::Environment.log_level
  logger.formatter = Dependabot::Logger::BasicFormatter.new
end

Sentry.init do |config|
  config.logger = Dependabot.logger
  config.project_root = File.expand_path("../../..", __dir__)

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
    pub|
    swift|
    devcontainers
  )}x

  config.before_send = ->(event, hint) { Dependabot::Sentry::Processor.process_chain(event, hint) }
  config.propagate_traces = false
end

require "dependabot/opentelemetry"
Dependabot::OpenTelemetry.configure

# Ecosystems
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
require "dependabot/swift"
require "dependabot/devcontainers"
