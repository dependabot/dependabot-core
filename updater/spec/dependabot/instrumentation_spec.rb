# frozen_string_literal: true

require "spec_helper"
require "dependabot/api_client"
require "dependabot/instrumentation"

RSpec.describe "dependabot instrumentation" do
  describe ".subscribe" do
    it "relays package manager versions to core" do
      allow(Dependabot::Environment).to receive(:job_id).and_return(1)
      allow(Dependabot::Environment).to receive(:token).and_return("some_token")

      expect_any_instance_of(Dependabot::ApiClient).to receive(:record_package_manager_version).with(
        1, "bundler", { "bundler" => "1" }
      )

      Dependabot.instrument(
        Dependabot::Notifications::FILE_PARSER_PACKAGE_MANAGER_VERSION_PARSED,
        { ecosystem: "bundler", package_managers: { "bundler" => "1" } }
      )
    end
  end
end
