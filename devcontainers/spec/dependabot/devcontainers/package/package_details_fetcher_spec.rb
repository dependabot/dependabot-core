# typed: false
# frozen_string_literal: true

require "cgi"
require "dependabot/credential"
require "dependabot/dependency_file"
require "dependabot/devcontainers/package/package_details_fetcher"
require "dependabot/devcontainers/version"
require "dependabot/package/package_release"
require "dependabot/registry_client"
require "excon"
require "json"
require "nokogiri"
require "sorbet-runtime"
require "spec_helper"
require "time"
require "dependabot/shared_helpers"

RSpec.describe Dependabot::Devcontainers::Package::PackageDetailsFetcher do
  describe "#fetch_package_releases" do
    subject(:fetcher) { described_class.new(dependency: dependency) }

    let(:dependency) do
      Dependabot::Dependency.new(
        name: dependency_name,
        version: dependency_version,
        requirements: requirements,
        package_manager: "devcontainers"
      )
    end
    let(:dependency_version) { "2.2.0" }
    let(:dependency_name) { "devcontainers/http" }
    let(:requirements) do
      [{
        file: "devcontainers.json",
        requirement: string_req,
        groups: [],
        source: nil
      }]
    end
    let(:string_req) { "1.0.0 <= v <= 2.2.0" }

    context "when the response is successful" do
      let(:response) { fixture("projects/devcontainers_json", "devcontainers-parser.json") }

      before do
        allow(Dependabot::SharedHelpers).to receive(:run_shell_command).and_return(response)
      end

      it "returns an array of package releases" do
        releases = fetcher.fetch_package_releases

        expect(releases.size).to eq(50)
        expect(releases[0].version.to_s).to eq("1")
        expect(releases[49].version.to_s).to eq("2.12.2")
      end
    end

    context "when the response is not successful" do
      before do
        allow(Dependabot::SharedHelpers).to receive(:run_shell_command).and_return(StandardError.new("Command failed"))
      end

      it "returns an empty array" do
        expect(fetcher.fetch_package_releases).to eq([])
      end
    end
  end
end
