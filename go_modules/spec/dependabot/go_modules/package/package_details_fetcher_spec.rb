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
      credentials: credentials
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

    context "when the subprocess fails with a resolvability error" do
      before do
        allow(Dependabot::SharedHelpers).to receive(:run_shell_command)
          .and_raise(Dependabot::SharedHelpers::HelperSubprocessFailed.new(
                       message: error_message,
                       error_context: {}
                     ))
      end

      context "when the error is 'no secure protocol found for repository'" do
        let(:error_message) { "no secure protocol found for repository example.com/mypackage" }

        it "returns the current version instead of raising" do
          result = fetch
          expect(result).to be_an(Array)
          expect(result.length).to eq(1)
          expect(result.first.version).to eq(Dependabot::GoModules::Version.new("0.3.23"))
        end
      end

      context "when the error is '404 Not Found'" do
        let(:error_message) { "go: module example.com/mypackage: 404 Not Found" }

        it "returns the current version instead of raising" do
          result = fetch
          expect(result).to be_an(Array)
          expect(result.length).to eq(1)
          expect(result.first.version).to eq(Dependabot::GoModules::Version.new("0.3.23"))
        end
      end

      context "when the error indicates a private repository" do
        let(:error_message) do
          "module github.com/private/repo: git ls-remote https://github.com/private/repo: exit status 128\n" \
            "If this is a private repository"
        end

        before do
          # Stub the inner `go list` call that ResolvabilityErrors.handle uses to
          # distinguish "private repo" from "bad revision". A non-zero exit status
          # tells it the repo is unreachable → GitDependenciesNotReachable.
          allow(Open3).to receive(:capture3).and_return(["", "", instance_double(Process::Status, success?: false)])
        end

        it "raises GitDependenciesNotReachable instead of returning current version" do
          expect { fetch }.to raise_error(Dependabot::GitDependenciesNotReachable)
        end
      end

      context "when the error does not match any resolvability pattern" do
        let(:error_message) { "some unexpected error" }

        it "raises DependencyFileNotResolvable" do
          expect { fetch }.to raise_error(Dependabot::DependencyFileNotResolvable)
        end
      end
    end
  end
end
