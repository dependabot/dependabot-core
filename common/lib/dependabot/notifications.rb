# frozen_string_literal: true

require "active_support"
require "active_support/notifications"

module Dependabot
  module Notifications
    FILE_PARSER_PACKAGE_MANAGER_VERSION_PARSED = "dependabot.file_parser.package_manager_version_parsed"
  end

  def self.instrument(name, payload = {})
    ActiveSupport::Notifications.instrument(name, payload)
  end

  def self.subscribe(pattern = nil, callback = nil, &block)
    ActiveSupport::Notifications.subscribe(pattern, callback, &block)
  end
end
