# frozen_string_literal: true

require "dependabot/logger"
require "dependabot/logger/formats"
require "dependabot/environment"

Dependabot.logger = Logger.new($stdout).tap do |logger|
  logger.level = Dependabot::Environment.log_level
  logger.formatter = Dependabot::Logger::BasicFormatter.new
end

require "dependabot/sentry"
Raven.configure do |config|
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
    pub
  )}x

  config.processors += [ExceptionSanitizer]
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
