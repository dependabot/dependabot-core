# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/credential"
require "dependabot/dependency_file"
require "dependabot/go_modules/package/package_details_fetcher"
require "dependabot/go_modules/go_mod_manifest"
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

    context "with typed manifest output" do
      let(:manifest_json) do
        JSON.generate("Exclude" => [{ "Path" => dependency_name, "Version" => "v0.9.0" }])
      end

      before do
        allow(Dependabot::SharedHelpers).to receive(:run_shell_command).and_return('{"Versions":["v1.0.0"]}')
        allow(Dependabot::SharedHelpers).to receive(:run_shell_command)
          .with("go mod edit -json").and_return(manifest_json)
      end

      it "preserves exclusions when fetching versions" do
        expect(fetch.map(&:version)).to eq([Dependabot::GoModules::Version.new("1.0.0")])
        expect(Dependabot::SharedHelpers).to have_received(:run_shell_command)
          .with("go mod edit -exclude=#{dependency_name}@v0.9.0")
      end

      [nil, false, [], { "Require" => [nil] }, { "Exclude" => [{ "Path" => "example.com/module" }] }].each do |data|
        context "with malformed manifest #{data.inspect}" do
          let(:manifest_json) { JSON.generate(data) }

          it "propagates the error instead of returning the current version or retrying" do
            expect { fetch }.to raise_error(
              Dependabot::GoModules::GoModManifest::InvalidOutput, %r{go mod edit -json for /go.mod:}
            )
            expect(Dependabot::SharedHelpers).to have_received(:run_shell_command).with("go mod edit -json").once
            expect(Dependabot::SharedHelpers).not_to have_received(:run_shell_command)
              .with(a_string_starting_with("go list"), anything)
          end
        end
      end

      [["unclassified command failure", 1], ["EOF", 2]].each do |message, attempts|
        context "when the manifest command fails with #{message}" do
          before do
            failure = Dependabot::SharedHelpers::HelperSubprocessFailed.new(message: message, error_context: {})
            allow(Dependabot::SharedHelpers).to receive(:run_shell_command)
              .with("go mod edit -json").and_raise(failure)
          end

          it "retains the existing error classification and retry count" do
            expect { fetch }.to raise_error(Dependabot::DependencyFileNotResolvable, message)
            expect(Dependabot::SharedHelpers).to have_received(:run_shell_command)
              .with("go mod edit -json").exactly(attempts).times
          end
        end
      end
    end

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

    context "with an Azure DevOps module path without _git" do
      let(:dependency_name) { "dev.azure.com/VaronisIO/da-cloud/be-protobuf.git" }

      before do
        allow(Dependabot::SharedHelpers).to receive(:run_shell_command).and_return("{}")

        allow(Dependabot::SharedHelpers).to receive(:run_shell_command)
          .with("go mod edit -json")
          .and_return("{}")

        allow(Dependabot::SharedHelpers).to receive(:run_shell_command)
          .with(
            "go list -m -versions -json dev.azure.com/VaronisIO/da-cloud/_git/be-protobuf",
            fingerprint: "go list -m -versions -json <dependency_name>"
          )
          .and_return('{"Versions":["v1.0.0"]}')
      end

      it "adds the _git segment before resolving available versions" do
        fetch

        expect(Dependabot::SharedHelpers)
          .to have_received(:run_shell_command)
          .with(
            "go list -m -versions -json dev.azure.com/VaronisIO/da-cloud/_git/be-protobuf",
            fingerprint: "go list -m -versions -json <dependency_name>"
          )
      end
    end

    context "with an Azure DevOps module path that already includes _git" do
      let(:dependency_name) { "dev.azure.com/VaronisIO/da-cloud/_git/be-protobuf.git" }

      before do
        allow(Dependabot::SharedHelpers).to receive(:run_shell_command).and_return("{}")

        allow(Dependabot::SharedHelpers).to receive(:run_shell_command)
          .with("go mod edit -json")
          .and_return("{}")

        allow(Dependabot::SharedHelpers).to receive(:run_shell_command)
          .with(
            "go list -m -versions -json dev.azure.com/VaronisIO/da-cloud/_git/be-protobuf.git",
            fingerprint: "go list -m -versions -json <dependency_name>"
          )
          .and_return('{"Versions":["v1.0.0"]}')
      end

      it "retains the .git suffix when _git is already present" do
        fetch

        expect(Dependabot::SharedHelpers)
          .to have_received(:run_shell_command)
          .with(
            "go list -m -versions -json dev.azure.com/VaronisIO/da-cloud/_git/be-protobuf.git",
            fingerprint: "go list -m -versions -json <dependency_name>"
          )
      end
    end

    context "with an Azure DevOps module path that includes a subdirectory" do
      let(:dependency_name) { "dev.azure.com/VaronisIO/da-cloud/be-protobuf.git/submodule" }

      before do
        allow(Dependabot::SharedHelpers).to receive(:run_shell_command).and_return("{}")

        allow(Dependabot::SharedHelpers).to receive(:run_shell_command)
          .with("go mod edit -json")
          .and_return("{}")

        allow(Dependabot::SharedHelpers).to receive(:run_shell_command)
          .with(
            "go list -m -versions -json dev.azure.com/VaronisIO/da-cloud/_git/be-protobuf/submodule",
            fingerprint: "go list -m -versions -json <dependency_name>"
          )
          .and_return('{"Versions":["v1.0.0"]}')
      end

      it "preserves the subdirectory while adding _git" do
        fetch

        expect(Dependabot::SharedHelpers)
          .to have_received(:run_shell_command)
          .with(
            "go list -m -versions -json dev.azure.com/VaronisIO/da-cloud/_git/be-protobuf/submodule",
            fingerprint: "go list -m -versions -json <dependency_name>"
          )
      end
    end

    context "with an Azure DevOps _git module path that includes a subdirectory" do
      let(:dependency_name) { "dev.azure.com/VaronisIO/da-cloud/_git/be-protobuf.git/submodule" }

      before do
        allow(Dependabot::SharedHelpers).to receive(:run_shell_command).and_return("{}")

        allow(Dependabot::SharedHelpers).to receive(:run_shell_command)
          .with("go mod edit -json")
          .and_return("{}")

        allow(Dependabot::SharedHelpers).to receive(:run_shell_command)
          .with(
            "go list -m -versions -json dev.azure.com/VaronisIO/da-cloud/_git/be-protobuf.git/submodule",
            fingerprint: "go list -m -versions -json <dependency_name>"
          )
          .and_return('{"Versions":["v1.0.0"]}')
      end

      it "retains .git and subdirectory when _git is already present" do
        fetch

        expect(Dependabot::SharedHelpers)
          .to have_received(:run_shell_command)
          .with(
            "go list -m -versions -json dev.azure.com/VaronisIO/da-cloud/_git/be-protobuf.git/submodule",
            fingerprint: "go list -m -versions -json <dependency_name>"
          )
      end
    end

    context "when the dependency path is a sub-package, not a module root" do
      let(:dependency_name) { "github.com/wasilibs/go-shellcheck/cmd/shellcheck" }
      let(:dependency_version) { "0.10.0" }

      before do
        allow(Dependabot::SharedHelpers).to receive(:run_shell_command).and_return("{}")

        allow(Dependabot::SharedHelpers).to receive(:run_shell_command)
          .with("go mod edit -json")
          .and_return("{}")

        # Full path returns no versions (sub-package, not a module)
        allow(Dependabot::SharedHelpers).to receive(:run_shell_command)
          .with(
            "go list -m -versions -json github.com/wasilibs/go-shellcheck/cmd/shellcheck",
            fingerprint: "go list -m -versions -json <dependency_name>"
          )
          .and_return('{"Path":"github.com/wasilibs/go-shellcheck/cmd/shellcheck","Version":"v0.10.0"}')

        # Intermediate path also fails
        allow(Dependabot::SharedHelpers).to receive(:run_shell_command)
          .with(
            "go list -m -versions -json github.com/wasilibs/go-shellcheck/cmd",
            fingerprint: "go list -m -versions -json <dependency_name>"
          )
          .and_raise(Dependabot::SharedHelpers::HelperSubprocessFailed.new(
                       message: "no matching versions", error_context: {}
                     ))

        # Module root returns versions
        allow(Dependabot::SharedHelpers).to receive(:run_shell_command)
          .with(
            "go list -m -versions -json github.com/wasilibs/go-shellcheck",
            fingerprint: "go list -m -versions -json <dependency_name>"
          )
          .and_return('{"Path":"github.com/wasilibs/go-shellcheck","Versions":["v0.10.0","v0.11.0","v0.11.1"]}')
      end

      it "falls back to the module root path and finds versions" do
        result = fetch

        expect(result.length).to eq(3)
        expect(result.map { |r| r.version.to_s }).to eq(%w(0.10.0 0.11.0 0.11.1))
      end
    end

    context "when the dependency path is already a module root" do
      let(:dependency_name) { "github.com/wasilibs/go-shellcheck" }
      let(:dependency_version) { "0.10.0" }

      before do
        allow(Dependabot::SharedHelpers).to receive(:run_shell_command).and_return("{}")

        allow(Dependabot::SharedHelpers).to receive(:run_shell_command)
          .with("go mod edit -json")
          .and_return("{}")

        allow(Dependabot::SharedHelpers).to receive(:run_shell_command)
          .with(
            "go list -m -versions -json github.com/wasilibs/go-shellcheck",
            fingerprint: "go list -m -versions -json <dependency_name>"
          )
          .and_return('{"Path":"github.com/wasilibs/go-shellcheck","Versions":["v0.10.0","v0.11.0","v0.11.1"]}')
      end

      it "returns versions directly without fallback" do
        result = fetch

        expect(result.length).to eq(3)
        expect(result.map { |r| r.version.to_s }).to eq(%w(0.10.0 0.11.0 0.11.1))
      end
    end

    context "when neither the full path nor shorter paths return versions" do
      let(:dependency_name) { "github.com/unknown/repo/cmd/tool" }
      let(:dependency_version) { "1.0.0" }

      before do
        allow(Dependabot::SharedHelpers).to receive(:run_shell_command).and_return("{}")

        allow(Dependabot::SharedHelpers).to receive(:run_shell_command)
          .with("go mod edit -json")
          .and_return("{}")

        # All paths return no versions
        allow(Dependabot::SharedHelpers).to receive(:run_shell_command)
          .with(
            "go list -m -versions -json github.com/unknown/repo/cmd/tool",
            fingerprint: "go list -m -versions -json <dependency_name>"
          )
          .and_return('{"Path":"github.com/unknown/repo/cmd/tool","Version":"v1.0.0"}')

        allow(Dependabot::SharedHelpers).to receive(:run_shell_command)
          .with(
            "go list -m -versions -json github.com/unknown/repo/cmd",
            fingerprint: "go list -m -versions -json <dependency_name>"
          )
          .and_raise(Dependabot::SharedHelpers::HelperSubprocessFailed.new(
                       message: "no matching versions", error_context: {}
                     ))

        allow(Dependabot::SharedHelpers).to receive(:run_shell_command)
          .with(
            "go list -m -versions -json github.com/unknown/repo",
            fingerprint: "go list -m -versions -json <dependency_name>"
          )
          .and_return('{"Path":"github.com/unknown/repo","Version":"v1.0.0"}')

        allow(Dependabot::SharedHelpers).to receive(:run_shell_command)
          .with(
            "go list -m -versions -json github.com/unknown",
            fingerprint: "go list -m -versions -json <dependency_name>"
          )
          .and_raise(Dependabot::SharedHelpers::HelperSubprocessFailed.new(
                       message: "no matching versions", error_context: {}
                     ))
      end

      it "falls back to the current version" do
        result = fetch

        expect(result.length).to eq(1)
        expect(result.first.version.to_s).to eq("0.3.23")
      end
    end
  end
end
