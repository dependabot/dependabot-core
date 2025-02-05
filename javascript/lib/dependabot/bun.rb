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
loader.ignore("#{__dir__}/../script", "#{__dir__}/../spec", "#{__dir__}/../dependabot-bun.gemspec")

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

Dependabot::PullRequestCreator::Labeler
  .register_label_details("bun", name: "javascript", colour: "168700")

Dependabot::Dependency.register_production_check("bun", ->(_) { true })

module Dependabot
  module Bun
    ECOSYSTEM = "bun"
  end
end
