# frozen_string_literal: true

require "spec_helper"

RSpec.shared_context "stub rubygems" do
  before do
    # Stub Bundler to stop it using a cached versions of Rubygems
    allow_any_instance_of(Bundler::CompactIndexClient::Updater).
      to receive(:etag_for).and_return("")

    # Stub the Rubygems index
    stub_request(:get, "https://index.rubygems.org/versions").
      to_return(status: 200, body: fixture("ruby", "rubygems-index"))

    # Stub the Rubygems response for each dependency we have a fixture for
    Dir[File.join("spec", "fixtures", "ruby", "rubygems-info-*")].each do |path|
      dep_name = path.split("/").last.gsub("rubygems-info-", "")
      stub_request(:get, "https://index.rubygems.org/info/#{dep_name}").
        to_return(
          status: 200,
          body: fixture("ruby", "rubygems-info-#{dep_name}")
        )
    end
  end
end
