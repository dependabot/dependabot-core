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

# rubocop:disable Metrics/BlockLength
Sentry.init do |config|
  config.release = ENV.fetch("DEPENDABOT_UPDATER_VERSION")
  config.logger = Dependabot.logger
  config.project_root = File.expand_path("../../..", __dir__)

  config.app_dirs_pattern = %r{(
    dependabot-updater/bin|
    dependabot-updater/config|
    dependabot-updater/lib|
    common|
    bundler|
    cargo|
    composer|
    conda|
    devcontainers|
    docker_compose|
    docker|
    dotnet_sdk|
    elm|
    git_submodules|
    github_actions|
    go_modules|
    gradle|
    helm|
    hex|
    maven|
    npm_and_yarn|
    nuget|
    pub|
    python|
    rust_toolchain|
    silent|
    swift|
    terraform|
    uv|
    vcpkg|
  )}x

  config.before_send = ->(event, hint) { Dependabot::Sentry.process_chain(event, hint) }
  config.propagate_traces = false
  config.instrumenter = ::Dependabot::OpenTelemetry.should_configure? ? :otel : :sentry
end
# rubocop:enable Metrics/BlockLength

Dependabot::OpenTelemetry.configure
Dependabot::Sorbet::Runtime.silently_report_errors!

# Ecosystems
require "dependabot/bun"
require "dependabot/bundler"
require "dependabot/cargo"
require "dependabot/composer"
require "dependabot/conda"
require "dependabot/devcontainers"
require "dependabot/docker_compose"
require "dependabot/docker"
require "dependabot/dotnet_sdk"
require "dependabot/elm"
require "dependabot/git_submodules"
require "dependabot/github_actions"
require "dependabot/go_modules"
require "dependabot/gradle"
require "dependabot/helm"
require "dependabot/hex"
require "dependabot/maven"
require "dependabot/npm_and_yarn"
require "dependabot/nuget"
require "dependabot/pub"
require "dependabot/python"
require "dependabot/rust_toolchain"
require "dependabot/silent"
require "dependabot/swift"
require "dependabot/terraform"
require "dependabot/uv"
require "dependabot/vcpkg"
