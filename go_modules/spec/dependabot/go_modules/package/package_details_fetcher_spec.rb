# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/credential"
require "dependabot/dependency_file"
require "dependabot/go_modules/package/package_details_fetcher"
require "dependabot/package/package_release"

RSpec.describe Dependabot::GoModules::Package::PackageDetailsFetcher do
  subject(:fetcher) do
    described_class.new(
      dependency: dependency,
      dependency_files: dependency_files,
      credentials: credentials,
      goprivate: "*"
    )
  end

  let(:dependency) do
    Dependabot::Dependency.new(
      name: dependency_name,
      version: "0.3.23",
      requirements: [{
        requirement: "==0.3.23",
        file: "go.mod",
        groups: ["dependencies"],
        source: nil
      }],
      package_manager: "go_modules"
    )
  end
  let(:files) { [go_mod, go_sum] }
  let(:go_mod_body) { fixture("projects", project_name, "go.mod") }
  let(:go_mod) do
    Dependabot::DependencyFile.new(name: "go.mod", content: go_mod_body)
  end
  let(:go_sum_body) { fixture("projects", project_name, "go.sum") }
  let(:go_sum) do
    Dependabot::DependencyFile.new(name: "go.sum", content: go_sum_body)
  end
  let(:credentials) { [] }
  let(:json_url) { "https://github.com/dependabot-fixtures/go-modules-lib" }
  let(:dependency_files) do
    [
      Dependabot::DependencyFile.new(
        name: "go.mod",
        content: go_mod_content
      )
    ]
  end
  let(:dependency_version) { "1.0.0" }
  let(:dependency_name) { "github.com/dependabot-fixtures/go-modules-lib" }
  let(:go_mod_content) do
    <<~GOMOD
      module foobar
      require #{dependency_name} v#{dependency_version}
    GOMOD
  end

  let(:latest_release) do
    Dependabot::Package::PackageRelease.new(
      version: Dependabot::GoModules::Version.new("1.0.0")
    )
  end

  describe "#fetch" do
    subject(:fetch) { fetcher.fetch_available_versions }

    context "with a valid response" do
      before do
        stub_request(:get, json_url)
          .to_return(
            status: 200,
            body: fixture("go_io_responses", "package_fetcher.json"),
            headers: { "Content-Type" => "application/json" }
          )
      end

      it "fetches versions information" do
        result = fetch

        first_result = result.first

        expect(first_result).to be_a(Dependabot::Package::PackageRelease)

        expect(first_result.version).to eq(latest_release.version)
        expect(first_result.package_type).to eq(latest_release.package_type)
      end
    end
  end
end
