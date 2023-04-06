# frozen_string_literal: true

require "spec_helper"
require "shared_contexts"
require "dependabot/dependency"
require "dependabot/dependency_file"
require "dependabot/bundler/update_checker/latest_version_finder"

RSpec.describe Dependabot::Bundler::UpdateChecker::LatestVersionFinder do
  let(:finder) do
    described_class.new(
      dependency: dependency,
      dependency_files: dependency_files,
      ignored_versions: ignored_versions,
      raise_on_ignored: raise_on_ignored,
      security_advisories: security_advisories,
      credentials: [{
        "type" => "git_source",
        "host" => "github.com",
        "username" => "x-access-token",
        "password" => "token"
      }],
      options: {}
    )
  end
  let(:dependency_files) { bundler_project_dependency_files("gemfile") }
  let(:bundler_version) { PackageManagerHelper.bundler_version }
  let(:ignored_versions) { [] }
  let(:raise_on_ignored) { false }
  let(:security_advisories) { [] }

  let(:dependency) do
    Dependabot::Dependency.new(
      name: dependency_name,
      version: current_version,
      requirements: requirements,
      package_manager: "bundler"
    )
  end
  let(:dependency_name) { "business" }
  let(:current_version) { "1.3" }
  let(:requirements) do
    [{
      file: "Gemfile",
      requirement: requirement_string,
      groups: [],
      source: source
    }]
  end
  let(:source) { nil }
  let(:requirement_string) { ">= 0" }

  let(:rubygems_url) { "https://rubygems.org/api/v1/" }

  describe "#latest_version_details" do
    subject { finder.latest_version_details }

    context "with a rubygems source" do
      before do
        rubygems_response = fixture("ruby", "rubygems_response_versions.json")
        stub_request(:get, rubygems_url + "versions/business.json").
          to_return(status: 200, body: rubygems_response)
      end

      its([:version]) { is_expected.to eq(Gem::Version.new("1.5.0")) }

      it "only hits Rubygems once" do
        finder.latest_version_details
        finder.latest_version_details
        expect(WebMock).
          to have_requested(:get, rubygems_url + "versions/business.json").once
      end

      context "when the gem isn't on Rubygems" do
        before do
          stub_request(:get, rubygems_url + "versions/business.json").
            to_return(status: 404, body: "This rubygem could not be found.")
        end

        it { is_expected.to be_nil }
      end

      context "with a gems.rb setup" do
        let(:dependency_files) { bundler_project_dependency_files("gems_rb") }

        its([:version]) { is_expected.to eq(Gem::Version.new("1.5.0")) }
      end

      context "when the gem is Bundler" do
        let(:dependency_files) { bundler_project_dependency_files("bundler_specified") }
        let(:dependency_name) { "bundler" }
        before do
          rubygems_response = fixture("ruby", "rubygems_response_versions.json")
          stub_request(:get, rubygems_url + "versions/bundler.json").
            to_return(status: 200, body: rubygems_response)
        end

        its([:version]) { is_expected.to eq(Gem::Version.new("1.5.0")) }

        context "wrapped in a source block" do
          let(:dependency_files) { bundler_project_dependency_files("bundler_specified_in_source_bundler_specified") }
          its([:version]) { is_expected.to eq(Gem::Version.new("1.5.0")) }
        end
      end

      context "raise_on_ignored when later versions are allowed" do
        let(:raise_on_ignored) { true }
        it "doesn't raise an error" do
          expect { subject }.to_not raise_error
        end
      end

      context "when the user is on the latest version" do
        let(:current_version) { "1.5.0" }
        its([:version]) { is_expected.to eq(Gem::Version.new("1.5.0")) }

        context "raise_on_ignored" do
          let(:raise_on_ignored) { true }
          it "doesn't raise an error" do
            expect { subject }.to_not raise_error
          end
        end
      end

      context "when the current version isn't known" do
        let(:current_version) { nil }

        context "raise_on_ignored" do
          let(:raise_on_ignored) { true }
          it "doesn't raise an error" do
            expect { subject }.to_not raise_error
          end
        end
      end

      context "when the dependency is a git dependency" do
        let(:current_version) { "a1b78a929dac93a52f08db4f2847d76d6cfe39bd" }

        context "raise_on_ignored" do
          let(:raise_on_ignored) { true }
          it "doesn't raise an error" do
            expect { subject }.to_not raise_error
          end
        end
      end

      context "when the user has ignored all later versions" do
        let(:ignored_versions) { ["> 1.3.0"] }

        its([:version]) { is_expected.to eq(Gem::Version.new("1.3.0")) }

        context "raise_on_ignored" do
          let(:raise_on_ignored) { true }
          it "raises an error" do
            expect { subject }.to raise_error(Dependabot::AllVersionsIgnored)
          end
        end
      end

      context "when the user is ignoring the latest version" do
        let(:ignored_versions) { [">= 1.5.0.a, < 1.6"] }
        its([:version]) { is_expected.to eq(Gem::Version.new("1.4.0")) }
      end

      context "when the user has ignored all versions" do
        let(:ignored_versions) { [">= 0"] }

        it "returns nil" do
          expect(subject).to be_nil
        end

        context "raise_on_ignored" do
          let(:raise_on_ignored) { true }
          it "raises an error" do
            expect { subject }.to raise_error(Dependabot::AllVersionsIgnored)
          end
        end
      end

      context "with a prerelease version specified" do
        let(:dependency_files) { bundler_project_dependency_files("prerelease_specified") }
        let(:requirement_string) { "~> 1.4.0.rc1" }

        before do
          rubygems_response = fixture("ruby", "rubygems_response_versions.json")
          stub_request(:get, rubygems_url + "versions/business.json").
            to_return(status: 200, body: rubygems_response)
        end
        its([:version]) { is_expected.to eq(Gem::Version.new("1.6.0.beta")) }
      end

      context "with a Ruby version specified" do
        let(:dependency_files) { bundler_project_dependency_files("explicit_ruby") }
        its([:version]) { is_expected.to eq(Gem::Version.new("1.5.0")) }
      end

      context "given a Gemfile that loads a .ruby-version file" do
        let(:dependency_files) { bundler_project_dependency_files("ruby_version_file") }

        its([:version]) { is_expected.to eq(Gem::Version.new("1.5.0")) }
      end

      context "with a gemspec and a Gemfile" do
        let(:dependency_files) { bundler_project_dependency_files("gemfile_small_example") }

        its([:version]) { is_expected.to eq(Gem::Version.new("1.5.0")) }

        context "with a dependency that only appears in the gemspec" do
          let(:dependency_files) { bundler_project_dependency_files("gemfile_small_example") }
          let(:dependency_name) { "octokit" }

          before do
            response = fixture("ruby", "rubygems_response_versions.json")
            stub_request(:get, rubygems_url + "versions/octokit.json").
              to_return(status: 200, body: response)
          end

          its([:version]) { is_expected.to eq(Gem::Version.new("1.5.0")) }

          context "when there is no default source" do
            let(:dependency_files) { bundler_project_dependency_files("imports_gemspec_no_default_source_no_lockfile") }
            its([:version]) { is_expected.to eq(Gem::Version.new("1.5.0")) }
          end
        end
      end

      context "with only a gemspec" do
        let(:dependency_files) { bundler_project_dependency_files("gemspec_small_example_no_lockfile") }

        its([:version]) { is_expected.to eq(Gem::Version.new("1.5.0")) }
      end

      context "with only a Gemfile" do
        let(:dependency_files) { bundler_project_dependency_files("no_lockfile") }

        its([:version]) { is_expected.to eq(Gem::Version.new("1.5.0")) }
      end
    end

    context "with a private rubygems source" do
      let(:dependency_files) { bundler_project_dependency_files("specified_source") }
      let(:source) { { type: "rubygems" } }
      let(:registry_url) { "https://repo.fury.io/greysteil/" }
      let(:gemfury_business_url) do
        "https://repo.fury.io/greysteil/api/v1/dependencies?gems=business"
      end

      before do
        # We only need to stub out the version callout since it would
        # otherwise call out to the internet in a shell command
        allow(Dependabot::Bundler::NativeHelpers).
          to receive(:run_bundler_subprocess).
          with({
            bundler_version: bundler_version,
            function: "dependency_source_type",
            options: anything,
            args: anything
          }).and_call_original

        allow(Dependabot::Bundler::NativeHelpers).
          to receive(:run_bundler_subprocess).
          with({
            bundler_version: bundler_version,
            function: "private_registry_versions",
            options: anything,
            args: anything
          }).
          and_return(
            ["1.5.0", "1.9.0", "1.10.0.beta"]
          )
      end

      its([:version]) { is_expected.to eq(Gem::Version.new("1.9.0")) }

      context "specified as the default source" do
        let(:dependency_files) { bundler_project_dependency_files("specified_default_source") }

        its([:version]) { is_expected.to eq(Gem::Version.new("1.9.0")) }
      end

      context "when the user is ignoring the latest version" do
        let(:ignored_versions) { [">= 1.9.0.a, < 2.0"] }
        its([:version]) { is_expected.to eq(Gem::Version.new("1.5.0")) }
      end

      let(:subprocess_error) do
        Dependabot::SharedHelpers::HelperSubprocessFailed.new(
          message: error_message,
          error_context: {},
          error_class: error_class
        )
      end

      context "that we don't have authentication details for", :bundler_v1_only do
        let(:error_message) do
          <<~ERR
            Authentication is required for repo.fury.io.
            Please supply credentials for this source. You can do this by running:
              bundle config repo.fury.io username:password
          ERR
        end

        let(:error_class) do
          "Bundler::Fetcher::AuthenticationRequiredError"
        end

        before do
          allow(Dependabot::Bundler::NativeHelpers).
            to receive(:run_bundler_subprocess).
            with({
              bundler_version: bundler_version,
              function: "private_registry_versions",
              options: anything,
              args: anything
            }).
            and_raise(subprocess_error)
        end

        it "blows up with a useful error" do
          error_class = Dependabot::PrivateSourceAuthenticationFailure
          expect { finder.latest_version_details }.
            to raise_error do |error|
              expect(error).to be_a(error_class)
              expect(error.source).to eq("repo.fury.io")
            end
        end
      end

      context "that we don't have authentication details for", :bundler_v2_only do
        let(:error_message) do
          <<~ERR
            Bad username or password for https://user:secret@repo.fury.io/greysteil/.
            Please double-check your credentials and correct them.
          ERR
        end

        let(:error_class) do
          "Bundler::Fetcher::BadAuthenticationError"
        end

        before do
          allow(Dependabot::Bundler::NativeHelpers).
            to receive(:run_bundler_subprocess).
            with({
              bundler_version: bundler_version,
              function: "private_registry_versions",
              options: anything,
              args: anything
            }).
            and_raise(subprocess_error)
        end

        it "blows up with a useful error" do
          error_class = Dependabot::PrivateSourceAuthenticationFailure
          expect { finder.latest_version_details }.
            to raise_error do |error|
              expect(error).to be_a(error_class)
              expect(error.source).to eq("https://repo.fury.io/<redacted>")
            end
        end
      end

      context "that we have bad authentication details for" do
        let(:error_message) do
          <<~ERR
            Bad username or password for https://user:secret@repo.fury.io/greysteil/.
            Please double-check your credentials and correct them.
          ERR
        end

        let(:error_class) do
          "Bundler::Fetcher::BadAuthenticationError"
        end

        before do
          allow(Dependabot::Bundler::NativeHelpers).
            to receive(:run_bundler_subprocess).
            with({
              bundler_version: bundler_version,
              function: "private_registry_versions",
              options: anything,
              args: anything
            }).
            and_raise(subprocess_error)
        end

        it "blows up with a useful error" do
          error_class = Dependabot::PrivateSourceAuthenticationFailure
          expect { finder.latest_version_details }.
            to raise_error do |error|
              expect(error).to be_a(error_class)
              expect(error.source).
                to eq("https://repo.fury.io/<redacted>")
            end
        end
      end

      context "that bad-requested, but was a private repo" do
        let(:error_message) do
          <<~ERR
            Could not fetch specs from https://repo.fury.io/greysteil/
          ERR
        end

        let(:error_class) do
          "Bundler::HTTPError"
        end

        before do
          allow(Dependabot::Bundler::NativeHelpers).
            to receive(:run_bundler_subprocess).
            with({
              bundler_version: bundler_version,
              function: "private_registry_versions",
              options: anything,
              args: anything
            }).
            and_raise(subprocess_error)
        end

        it "blows up with a useful error" do
          expect { finder.latest_version_details }.
            to raise_error do |error|
              expect(error).to be_a(Dependabot::PrivateSourceTimedOut)
              expect(error.source).
                to eq("https://repo.fury.io/<redacted>")
            end
        end
      end

      context "that doesn't have details of the gem" do
        before do
          allow(Dependabot::Bundler::NativeHelpers).
            to receive(:run_bundler_subprocess).
            with({
              bundler_version: bundler_version,
              function: "private_registry_versions",
              options: anything,
              args: anything
            }).
            and_return(
              []
            )
        end

        it { is_expected.to be_nil }
      end
    end

    context "given a git source" do
      let(:dependency_files) { bundler_project_dependency_files("git_source") }

      context "that is the gem we're checking for" do
        let(:dependency_name) { "business" }
        let(:current_version) { "a1b78a929dac93a52f08db4f2847d76d6cfe39bd" }
        let(:source) do
          {
            type: "git",
            url: "https://github.com/dependabot-fixtures/business",
            branch: "master",
            ref: "a1b78a9" # Pinned, to ensure we unpin
          }
        end

        it "fetches the latest SHA-1 hash" do
          commit_sha = finder.latest_version_details[:commit_sha]
          expect(commit_sha).to match(/^[0-9a-f]{40}$/)
          expect(commit_sha).to_not eq(current_version)
        end

        context "when the gem has a bad branch" do
          let(:dependency_files) { bundler_project_dependency_files("bad_branch_business") }
          let(:source) do
            {
              type: "git",
              url: "https://github.com/dependabot-fixtures/business",
              branch: "bad_branch",
              ref: "bad_branch"
            }
          end

          it "raises a helpful error" do
            expect { finder.latest_version_details }.
              to raise_error do |error|
                expect(error).to be_a Dependabot::GitDependencyReferenceNotFound
                expect(error.dependency).to eq("business")
              end
          end
        end
      end

      context "that is not the gem we're checking" do
        let(:dependency_name) { "statesman" }

        before do
          stub_request(:get, rubygems_url + "versions/statesman.json").
            to_return(
              status: 200,
              body: fixture("ruby", "rubygems_response_versions.json")
            )
        end

        its([:version]) { is_expected.to eq(Gem::Version.new("1.5.0")) }

        context "that is private" do
          let(:dependency_files) { bundler_project_dependency_files("private_git_source") }

          its([:version]) { is_expected.to eq(Gem::Version.new("1.5.0")) }
        end
      end
    end

    context "given a path source" do
      let(:dependency_files) { bundler_project_dependency_files("path_source") }

      before do
        rubygems_response = fixture("ruby", "rubygems_response_versions.json")
        stub_request(:get, rubygems_url + "versions/business.json").
          to_return(status: 200, body: rubygems_response)
      end

      context "with a downloaded gemspec" do
        let(:dependency_files) { bundler_project_dependency_files("path_source") }

        context "that is not the gem we're checking" do
          its([:version]) { is_expected.to eq(Gem::Version.new("1.5.0")) }
        end

        context "that is the gem we're checking" do
          let(:dependency_name) { "example" }
          let(:source) { { type: "path" } }

          it { is_expected.to be_nil }
        end
      end
    end
  end

  describe "#lowest_security_fix_version" do
    subject { finder.lowest_security_fix_version }

    let(:current_version) { "1.1.0" }
    let(:security_advisories) do
      [
        Dependabot::SecurityAdvisory.new(
          dependency_name: dependency_name,
          package_manager: "bundler",
          vulnerable_versions: ["<= 1.3.0"]
        )
      ]
    end

    context "with a rubygems source" do
      before do
        rubygems_response = fixture("ruby", "rubygems_response_versions.json")
        stub_request(:get, rubygems_url + "versions/business.json").
          to_return(status: 200, body: rubygems_response)
      end

      it { is_expected.to eq(Gem::Version.new("1.4.0")) }
    end

    context "with a private rubygems source" do
      let(:dependency_files) { bundler_project_dependency_files("specified_source") }
      let(:source) { { type: "rubygems" } }
      let(:registry_url) { "https://repo.fury.io/greysteil/" }
      let(:gemfury_business_url) do
        "https://repo.fury.io/greysteil/api/v1/dependencies?gems=business"
      end

      before do
        # We only need to stub out the version callout since it would
        # otherwise call out to the internet in a shell command
        allow(Dependabot::Bundler::NativeHelpers).
          to receive(:run_bundler_subprocess).
          with({
            bundler_version: bundler_version,
            function: "dependency_source_type",
            options: anything,
            args: anything
          }).and_call_original

        allow(Dependabot::Bundler::NativeHelpers).
          to receive(:run_bundler_subprocess).
          with({
            bundler_version: bundler_version,
            function: "private_registry_versions",
            options: anything,
            args: anything
          }).
          and_return(
            ["1.5.0", "1.9.0", "1.10.0.beta"]
          )
      end

      it { is_expected.to eq(Gem::Version.new("1.5.0")) }
    end

    context "with a git source" do
      let(:dependency_files) { bundler_project_dependency_files("git_source") }

      it { is_expected.to be_nil }
    end

    context "with a path source" do
      let(:dependency_files) { bundler_project_dependency_files("path_source") }

      let(:dependency_name) { "example" }
      let(:source) { { type: "path" } }

      it { is_expected.to be_nil }
    end
  end
end
