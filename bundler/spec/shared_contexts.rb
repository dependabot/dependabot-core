# typed: false
# frozen_string_literal: true

require "spec_helper"

require "bundler/compact_index_client"
require "bundler/compact_index_client/updater"

RSpec.shared_context "when stubbing rubygems compact index" do
  before do
    # Stub the Rubygems index
    stub_request(:get, "https://index.rubygems.org/versions")
      .to_return(
        status: 200,
        body: fixture("rubygems_responses", "index")
      )

    # Stub the Rubygems response for each dependency we have a fixture for
    fixtures =
      Dir[File.join("spec", "fixtures", "rubygems_responses", "info-*")]
    fixtures.each do |path|
      dep_name = path.split("/").last.gsub("info-", "")
      stub_request(:get, "https://index.rubygems.org/info/#{dep_name}")
        .to_return(
          status: 200,
          body: fixture("rubygems_responses", "info-#{dep_name}")
        )
    end
  end
end

RSpec.shared_context "when stubbing rubygems versions api" do
  before do
    # Stub the Rubygems response for each dependency we have a fixture for
    fixtures =
      Dir[
        File.join("spec", "fixtures", "rubygems_responses",
                  "versions-*")
      ]
    fixtures.each do |path|
      dep_name = path.split("/").last.gsub("versions-", "")
      stub_request(:get, "https://rubygems.org/api/v1/versions/#{dep_name}")
        .to_return(
          status: 200,
          body: fixture("rubygems_responses", "versions-#{dep_name}")
        )
    end
  end
end
