# frozen_string_literal: true

require "dependabot/api_client"
require "dependabot/notifications"
require "active_support/notifications"
require "dependabot/environment"

Dependabot.subscribe(Dependabot::Notifications::FILE_PARSER_PACKAGE_MANAGER_VERSION_PARSED) do |*args|
  event = ActiveSupport::Notifications::Event.new(*args)
  ecosystem = event.payload[:ecosystem]
  package_managers = event.payload[:package_managers]

  next unless ecosystem && package_managers

  Dependabot::ApiClient.new(Dependabot::Environment.api_url, Dependabot::Environment.token).
    record_package_manager_version(
      Dependabot::Environment.job_id, ecosystem, package_managers
    )
end
