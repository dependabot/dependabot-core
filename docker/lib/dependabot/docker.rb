# typed: strong
# frozen_string_literal: true

require "zeitwerk"

loader = Zeitwerk::Loader.new

# Set autoload paths for common/lib, excluding files whose content does not match the filename
loader.push_dir(File.join(__dir__, "../../../common/lib"))
loader.ignore(File.join(__dir__, "../../../common/lib/dependabot/errors.rb"))
loader.ignore(File.join(__dir__, "../../../common/lib/dependabot/logger.rb"))
loader.ignore(File.join(__dir__, "../../../common/lib/dependabot/notices.rb"))
loader.ignore(File.join(__dir__, "../../../common/lib/dependabot/clients/codecommit.rb"))

loader.push_dir(File.join(__dir__, ".."))
loader.ignore("#{__dir__}/../script", "#{__dir__}/../spec", "#{__dir__}/../dependabot-docker.gemspec", "docker_compose")

loader.on_load do |_file|
  require "json"
  require "sorbet-runtime"
  require "dependabot/errors"
  require "dependabot/logger"
  require "dependabot/notices"
  require "dependabot/clients/codecommit"
end

loader.log! if ENV["DEBUG"]
loader.setup

require_relative "docker_compose"

Dependabot::PullRequestCreator::Labeler
  .register_label_details("docker", name: "docker", colour: "21ceff")

Dependabot::Dependency.register_production_check("docker", ->(_) { true })


