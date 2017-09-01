# frozen_string_literal: true
require "octokit"
require "spec_helper"
require "dependabot/dependency"
require "dependabot/metadata_finders/cocoa/cocoa_pods"
require_relative "../shared_examples_for_metadata_finders"

RSpec.describe Dependabot::MetadataFinders::Cocoa::CocoaPods do
  it_behaves_like "a dependency metadata finder"

  let(:dependency) do
    Dependabot::Dependency.new(
      name: dependency_name,
      version: "1.0",
      previous_version: "0.9",
      requirements: [{
        requirement: "~> 1.0.0",
        file: "Podfile",
        groups: []
      }],
      previous_requirements: [{
        requirement: "~> 0.9.0",
        file: "Podfile",
        groups: []
      }],
      package_manager: "cocoapods"
    )
  end
  subject(:finder) do
    described_class.new(dependency: dependency, github_client: github_client)
  end
  let(:github_client) { Octokit::Client.new(access_token: "token") }
  let(:dependency_name) { "Alamofire" }

  describe "#source_url" do
    subject(:source_url) { finder.source_url }
    let(:cocoapods_url) { "https://cocoapods.org/pods/Alamofire/inline" }
    let(:cocoapods_response_code) { 200 }

    before do
      stub_request(:get, cocoapods_url).
        to_return(status: cocoapods_response_code, body: cocoapods_response)
    end

    context "when there is a github link in the Cocoapods response" do
      let(:cocoapods_response) { fixture("cocoa", "cocoapods_response.html") }

      it { is_expected.to eq("https://github.com/Alamofire/Alamofire") }

      it "caches the call to cocoapods" do
        2.times { source_url }
        expect(WebMock).to have_requested(:get, cocoapods_url).once
      end
    end

    context "when the pod isn't on Cocoapods" do
      let(:cocoapods_response_code) { 404 }
      let(:cocoapods_response) { fixture("cocoa", "cocoapods_not_found.html") }

      it { is_expected.to be_nil }
    end
  end
end
