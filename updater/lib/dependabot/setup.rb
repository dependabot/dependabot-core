# typed: strict
# frozen_string_literal: true

require "sentry-ruby"
require "sorbet-runtime"

require "dependabot/environment"
require "dependabot/logger"
require "dependabot/logger/formats"
require "dependabot/opentelemetry"
require "dependabot/sentry"
require "dependabot/sorbet/runtime"

Dependabot.logger = Logger.new($stdout).tap do |logger|
  logger.level = Dependabot::Environment.log_level
  logger.formatter = Dependabot::Logger::BasicFormatter.new
end

Sentry.init do |config|
  config.release = ENV.fetch("DEPENDABOT_UPDATER_VERSION")
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
    maven_osv|
    hex|
    cargo|
    go_modules|
    npm_and_yarn|
    bundler|
    pub|
    silent|
    swift|
    devcontainers
  )}x

  config.before_send = ->(event, hint) { Dependabot::Sentry.process_chain(event, hint) }
  config.propagate_traces = false
  config.instrumenter = ::Dependabot::OpenTelemetry.should_configure? ? :otel : :sentry
end

Dependabot::OpenTelemetry.configure
Dependabot::Sorbet::Runtime.silently_report_errors!

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
require "dependabot/maven_osv"
require "dependabot/hex"
require "dependabot/cargo"
require "dependabot/go_modules"
require "dependabot/npm_and_yarn"
require "dependabot/bundler"
require "dependabot/pub"
require "dependabot/silent"
require "dependabot/swift"
require "dependabot/devcontainers"
