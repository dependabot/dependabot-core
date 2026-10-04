# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency"
require "dependabot/dependency_file"
require "dependabot/go_modules/native_helpers"
require "dependabot/go_modules/update_checker/latest_version_finder"
require "dependabot/go_modules/module_info"

RSpec.describe Dependabot::GoModules::UpdateChecker::LatestVersionFinder do
  let(:dependency_name) { "github.com/dependabot-fixtures/go-modules-lib" }

  let(:dependency_version) { "1.0.0" }

  let(:security_advisories) { [] }

  let(:dependency) do
    Dependabot::Dependency.new(
      name: dependency_name,
      version: dependency_version,
      package_manager: "go_modules",
      requirements: [{
        file: "go.mod",
        requirement: dependency_version,
        groups: [],
        source: { type: "default", source: dependency_name }
      }]
    )
  end

  let(:go_mod_content) do
    <<~GOMOD
      module foobar
      require #{dependency_name} v#{dependency_version}
    GOMOD
  end

  let(:dependency_files) do
    [
      Dependabot::DependencyFile.new(
        name: "go.mod",
        content: go_mod_content
      )
    ]
  end

  let(:ignored_versions) { [] }

  let(:raise_on_ignored) { false }

  let(:cooldown_options) { nil }

  let(:finder) do
    described_class.new(
      dependency: dependency,
      dependency_files: dependency_files,
      credentials: [],
      ignored_versions: ignored_versions,
      security_advisories: security_advisories,
      raise_on_ignored: raise_on_ignored,
      cooldown_options: cooldown_options
    )
  end

  before do
    ENV["GOTOOLCHAIN"] = "local"
    ENV["GOPRIVATE"] = "*"
  end

  after do
    ENV.delete("GOPRIVATE")
  end

  describe "#latest_version" do
    context "when there's a newer major version but not a new minor version" do
      before do
        ENV["GOPRIVATE"] = "github.com/dependabot-fixtures"
        allow(Dependabot::SharedHelpers)
          .to receive(:run_shell_command).and_call_original
      end

      it "returns the latest minor version for the dependency's current major version" do
        expect(finder.latest_version).to eq(Dependabot::GoModules::Version.new("1.1.0"))
      end

      context "with an unrestricted goprivate" do
        let(:goprivate) { "" }

        it "returns the latest minor version for the dependency's current major version" do
          # The Go proxy can return unexpected results, so better to check that the env was set with a spy
          expect(finder.latest_version).instance_of?(Dependabot::GoModules::Version)

          expect(Dependabot::SharedHelpers)
            .to have_received(:run_shell_command)
            .with("go list -m -versions -json github.com/dependabot-fixtures/go-modules-lib",
                  { fingerprint: "go list -m -versions -json <dependency_name>" })
        end
      end

      context "with an org specific goprivate" do
        let(:goprivate) { "github.com/dependabot-fixtures/*" }

        it "returns the latest minor version for the dependency's current major version" do
          expect(finder.latest_version).to eq(Dependabot::GoModules::Version.new("1.1.0"))
        end
      end
    end

    context "when already on the latest version" do
      let(:dependency_name) { "github.com/dependabot-fixtures/go-modules-lib/v3" }
      let(:dependency_version) { "3.0.0" }

      it "returns the current version" do
        expect(finder.latest_version).to eq(Dependabot::GoModules::Version.new("3.0.0"))
      end
    end

    context "with a go.mod excluded version" do
      let(:go_mod_content) do
        <<~GOMOD
          module foobar
          require #{dependency_name} v#{dependency_version}
          exclude #{dependency_name} v1.1.0
        GOMOD
      end

      it "doesn't return to the excluded version" do
        expect(finder.latest_version).to eq(Dependabot::GoModules::Version.new("1.0.6"))
      end
    end

    context "with Dependabot-ignored versions" do
      let(:ignored_versions) { ["> 1.0.1"] }

      it "doesn't return Dependabot-ignored versions" do
        expect(finder.latest_version).to eq(Dependabot::GoModules::Version.new("1.0.1"))
      end
    end

    context "when on a pre-release" do
      let(:dependency_version) { "1.2.0-pre1" }

      it "returns newest pre-release" do
        expect(finder.latest_version).to eq(Dependabot::GoModules::Version.new("1.2.0-pre2"))
      end
    end

    context "when on a stable release and a newer prerelease is available" do
      it "returns the newest non-prerelease" do
        expect(finder.latest_version).to eq(Dependabot::GoModules::Version.new("1.1.0"))
      end
    end

    context "when dealing with a Git pseudo-version with pre-releases available" do
      let(:dependency_version) { "1.0.0-20181018214848-ab544413d0d3" }

      it "returns the latest pre-release" do
        # Since a pseudo-version is always a pre-release, those aren't filtered.
        # Here there was the choice to go to v1.1.0 or v1.2.0 pre-release, and it chose
        # the largest since being on a pre-release means all pre-releases are considered.
        expect(finder.latest_version).to eq(Dependabot::GoModules::Version.new("1.2.0-pre2"))
      end
    end

    context "when dealing with a Git psuedo-version with releases available" do
      let(:dependency_version) { "0.0.0-20201021035429-f5854403a974" }
      let(:dependency_name) { "golang.org/x/net" }
      let(:ignored_versions) { ["> 0.8.0"] }

      it "picks the latest version not ignored" do
        expect(finder.latest_version).to eq(Dependabot::GoModules::Version.new("0.8.0"))
      end
    end

    context "when dealing with a Git pseudo-version that is later than all releases" do
      let(:dependency_version) { "1.2.0-pre2.0.20181018214848-1f3e41dce654" }

      it "doesn't downgrade the dependency" do
        expect(finder.latest_version).to eq(dependency_version)
      end
    end

    context "when the package url returns 404" do
      let(:dependency_files) { [go_mod] }
      let(:dependency_name) { "example.com/test/package" }
      let(:dependency_version) { "1.7.0" }
      let(:go_mod) do
        Dependabot::DependencyFile.new(
          name: "go.mod",
          content: fixture("projects", "missing_package", "go.mod")
        )
      end

      it "raises a DependencyFileNotResolvable error" do
        error_class = Dependabot::DependencyFileNotResolvable
        expect { finder.latest_version }
          .to raise_error(error_class) do |error|
          expect(error.message).to include("example.com/test/package")
        end
      end
    end

    context "when the package url doesn't include any valid meta tags" do
      let(:dependency_files) { [go_mod] }
      let(:dependency_name) { "example.com/web/dependabot.com" }
      let(:dependency_version) { "1.7.0" }
      let(:go_mod) do
        Dependabot::DependencyFile.new(
          name: "go.mod",
          content: fixture("projects", "missing_meta_tag", "go.mod")
        )
      end

      it "raises a DependencyFileNotResolvable error" do
        error_class = Dependabot::DependencyFileNotResolvable
        expect { finder.latest_version }
          .to raise_error(error_class) do |error|
          expect(error.message).to include("example.com/web/dependabot.com")
        end
      end
    end

    context "when the package url is internal/invalid" do
      let(:dependency_files) { [go_mod] }
      let(:dependency_name) { "pkg-errors" }
      let(:dependency_version) { "1.0.0" }
      let(:go_mod) do
        Dependabot::DependencyFile.new(
          name: "go.mod",
          content: fixture("projects", "unrecognized_import", "go.mod")
        )
      end

      it "raises a DependencyFileNotResolvable error" do
        error_class = Dependabot::DependencyFileNotResolvable
        expect { finder.latest_version }
          .to raise_error(error_class) do |error|
          expect(error.message).to include("pkg-errors")
        end
      end
    end

    context "when the dependency's major version is invalid because it's not specified in its go.mod" do
      let(:dependency_name) { "github.com/dependabot-fixtures/go-modules-lib/v2" }
      let(:dependency_version) { "2.0.0" }

      it "raises a DependencyFileNotResolvable error" do
        error_class = Dependabot::DependencyFileNotResolvable
        expect { finder.latest_version }
          .to raise_error(error_class) do |error|
          expect(error.message).to include("github.com/dependabot-fixtures/go-modules-lib/v2")
          expect(error.message).to include("version \"v2.0.0\" invalid")
        end
      end
    end

    context "when the dependency's major version is invalid because not properly imported" do
      let(:dependency_name) { "github.com/dependabot-fixtures/go-modules-lib" }
      let(:dependency_version) { "3.0.0" }

      it "raises a DependencyFileNotResolvable error" do
        error_class = Dependabot::DependencyFileNotResolvable
        expect { finder.latest_version }
          .to raise_error(error_class) do |error|
          expect(error.message).to include("github.com/dependabot-fixtures/go-modules-lib")
          expect(error.message).to include("version \"v3.0.0\" invalid")
        end
      end
    end

    context "when the dependency's Go version isn't supported by Dependabot" do
      let(:dependency_name) { "github.com/dependabot-fixtures/future-go" }
      let(:dependency_version) { "0.0.0-1" }

      it "returns the correct release number" do
        expect(finder.latest_version).to eq(Dependabot::GoModules::Version.new("1.0.0"))
      end
    end

    context "when the module is unreachable" do
      let(:dependency_files) { [go_mod] }
      let(:dependency_name) { "github.com/dependabot-fixtures/go-modules-private" }
      let(:dependency_version) { "1.0.0" }
      let(:go_mod) do
        Dependabot::DependencyFile.new(
          name: "go.mod",
          content: fixture("projects", "unreachable_dependency", "go.mod")
        )
      end

      it "raises a GitDependenciesNotReachable error" do
        error_class = Dependabot::GitDependenciesNotReachable
        expect { finder.latest_version }
          .to raise_error(error_class) do |error|
          expect(error.message).to include("github.com/dependabot-fixtures/go-modules-private")
          expect(error.dependency_urls)
            .to eq(["github.com/dependabot-fixtures/go-modules-private"])
        end
      end

      context "with an unrestricted goprivate" do
        before { ENV["GOPRIVATE"] = "" }

        it "raises a GitDependenciesNotReachable error" do
          error_class = Dependabot::GitDependenciesNotReachable
          expect { finder.latest_version }
            .to raise_error(error_class) do |error|
            expect(error.message).to include("github.com/dependabot-fixtures/go-modules-private")
            expect(error.dependency_urls)
              .to eq(["github.com/dependabot-fixtures/go-modules-private"])
          end
        end
      end

      context "with an org specific goprivate" do
        before { ENV["GOPRIVATE"] = "github.com/dependabot-fixtures/*" }

        it "raises a GitDependenciesNotReachable error" do
          error_class = Dependabot::GitDependenciesNotReachable
          expect { finder.latest_version }
            .to raise_error(error_class) do |error|
            expect(error.message).to include("github.com/dependabot-fixtures/go-modules-private")
            expect(error.dependency_urls)
              .to eq(["github.com/dependabot-fixtures/go-modules-private"])
          end
        end
      end
    end

    context "with a retracted update version" do
      # latest release v1.0.1 is retracted
      let(:dependency_name) { "github.com/dependabot-fixtures/go-modules-retracted" }

      it "doesn't return the retracted version" do
        expect(finder.latest_version).to eq(Dependabot::GoModules::Version.new("1.0.0"))
      end
    end

    context "when the latest version is an '+incompatible' version" do # https://golang.org/ref/mod#incompatible-versions
      let(:dependency_name) { "github.com/dependabot-fixtures/go-modules-incompatible" }
      let(:dependency_version) { "2.0.0+incompatible" }

      it "returns the current version" do
        expect(finder.latest_version).to eq(Dependabot::GoModules::Version.new("2.0.0+incompatible"))
      end
    end

    context "when raise_on_ignored is true" do
      let(:raise_on_ignored) { true }

      context "when a later version is allowed" do
        let(:dependency_version) { "1.0.0" }
        let(:ignored_versions) { ["= 1.0.1"] }

        it "doesn't raise an error" do
          expect { finder.latest_version }.not_to raise_error
        end
      end

      context "when already on the latest version" do
        let(:dependency_version) { "1.1.0" }
        let(:ignored_versions) { ["> 1.1.0"] }

        it "doesn't raise an error" do
          expect { finder.latest_version }.not_to raise_error
        end
      end

      context "when all later versions are ignored" do
        let(:dependency_version) { "1.0.1" }
        let(:ignored_versions) { ["> 1.0.1"] }

        it "raises AllVersionsIgnored" do
          expect { finder.latest_version }
            .to raise_error(Dependabot::AllVersionsIgnored)
        end
      end
    end
  end

  describe "#latest_version with cooldown options" do
    context "when there's a newer major version and release date is still in cooldown" do
      before do
        allow(Dependabot::SharedHelpers)
          .to receive(:run_shell_command).and_call_original

        allow(Time).to receive(:now).and_return(Time.parse("2018-10-25T17:30:00.000Z"))
      end

      let(:cooldown_options) do
        Dependabot::Package::ReleaseCooldownOptions.new(
          default_days: 7,
          semver_major_days: 7,
          semver_minor_days: 7,
          semver_patch_days: 7,
          include: [],
          exclude: []
        )
      end

      it "returns the latest minor version for the dependency's current major version" do
        expect(finder.latest_version).to be_nil
      end

      context "with an org specific goprivate" do
        before { ENV["GOPRIVATE"] = "github.com/dependabot-fixtures/*" }

        it "returns the latest minor version for the dependency's current major version" do
          expect(finder.latest_version).to be_nil
        end
      end
    end

    context "when there's a newer major version and release date is out of cooldown" do
      before do
        allow(Dependabot::SharedHelpers)
          .to receive(:run_shell_command).and_call_original

        allow(Time).to receive(:now).and_return(Time.parse("2018-10-30T17:30:00.000Z"))
      end

      let(:cooldown_options) do
        Dependabot::Package::ReleaseCooldownOptions.new(
          default_days: 7,
          semver_major_days: 7,
          semver_minor_days: 7,
          semver_patch_days: 7,
          include: [],
          exclude: []
        )
      end

      it "returns the latest minor version for the dependency's current major version" do
        expect(finder.latest_version).to eq(Dependabot::GoModules::Version.new("1.1.0"))
      end

      context "with an org specific goprivate" do
        before { ENV["GOPRIVATE"] = "github.com/dependabot-fixtures/*" }

        it "returns the latest minor version for the dependency's current major version" do
          expect(finder.latest_version).to eq(Dependabot::GoModules::Version.new("1.1.0"))
        end
      end
    end

    context "when there's a newer major version and fetching release date is not successful" do
      before do
        allow(Dependabot::SharedHelpers)
          .to receive(:run_shell_command).and_call_original
      end

      let(:dependency_version) { "0.0.0" }
      let(:dependency_name) { "github.com/x/x" }

      let(:cooldown_options) do
        Dependabot::Package::ReleaseCooldownOptions.new(
          default_days: 7,
          semver_major_days: 7,
          semver_minor_days: 7,
          semver_patch_days: 7,
          include: [],
          exclude: []
        )
      end

      it "returns the latest resolvable version" do
        expect(finder.latest_version).to eq(Dependabot::GoModules::Version.new("0.0.0"))
      end
    end
  end

  describe "#latest_version with module response decoding" do
    let(:cooldown_options) { Dependabot::Package::ReleaseCooldownOptions.new(default_days: 7) }
    let(:version_query) { "go list -m -versions -json #{dependency_name}" }
    let(:version_fingerprint) { "go list -m -versions -json <dependency_name>" }
    let(:timestamp_fingerprint) { "go list -m -json <dependency_name>" }
    let(:newest_query) { "go list -m -json #{dependency_name}@v1.3.0" }
    let(:middle_query) { "go list -m -json #{dependency_name}@v1.2.0" }
    let(:oldest_query) { "go list -m -json #{dependency_name}@v1.1.0" }
    let(:newest_response) { '{"Time":"2024-06-14T00:00:00Z"}' }
    let(:middle_response) { '{"Time":"2024-06-01T00:00:00Z"}' }
    let(:oldest_response) { '{"Time":"2024-05-01T00:00:00Z"}' }

    before do
      allow(Time).to receive(:now).and_return(Time.utc(2024, 6, 15))
      allow(Dependabot::SharedHelpers).to receive(:run_shell_command)
        .with(a_string_starting_with("git "), any_args).and_call_original
      allow(Dependabot::SharedHelpers).to receive(:run_shell_command).with("go mod edit -json").and_return("{}")
      allow(Dependabot::SharedHelpers).to receive(:run_shell_command)
        .with(version_query, fingerprint: version_fingerprint).and_return('{"Versions":["v1.1.0","v1.2.0","v1.3.0"]}')
      allow(Dependabot::SharedHelpers).to receive(:run_shell_command)
        .with(newest_query, fingerprint: timestamp_fingerprint).and_return(newest_response)
      allow(Dependabot::SharedHelpers).to receive(:run_shell_command)
        .with(middle_query, fingerprint: timestamp_fingerprint).and_return(middle_response)
      allow(Dependabot::SharedHelpers).to receive(:run_shell_command)
        .with(oldest_query, fingerprint: timestamp_fingerprint).and_return(oldest_response)
    end

    it "updates cached release objects lazily and stops at the first eligible candidate" do
      releases = finder.available_versions
      newest, middle, oldest = releases
      details = newest.details

      expect(finder.latest_version).to eq(Dependabot::GoModules::Version.new("1.2.0"))
      expect(finder.available_versions).to equal(releases)
      expect(finder.available_versions.first).to equal(newest)
      expect(newest.released_at).to eq(Time.utc(2024, 6, 14))
      expect(middle.released_at).to eq(Time.utc(2024, 6, 1))
      expect(oldest.released_at).to be_nil
      expect(newest.details).to equal(details)
      expect(newest.details).to eq("version_string" => "v1.3.0")
      expect(Dependabot::SharedHelpers).not_to have_received(:run_shell_command)
        .with(oldest_query, fingerprint: timestamp_fingerprint)
    end

    it "does not repeat requests for a cached selection" do
      2.times { expect(finder.latest_version).to eq(Dependabot::GoModules::Version.new("1.2.0")) }

      expect(Dependabot::SharedHelpers).to have_received(:run_shell_command)
        .with(version_query, fingerprint: version_fingerprint).once
      expect(Dependabot::SharedHelpers).to have_received(:run_shell_command)
        .with(newest_query, fingerprint: timestamp_fingerprint).once
      expect(Dependabot::SharedHelpers).to have_received(:run_shell_command)
        .with(middle_query, fingerprint: timestamp_fingerprint).once
    end

    context "without cooldown" do
      let(:cooldown_options) { nil }

      it "does not query timestamps" do
        expect(finder.latest_version).to eq(Dependabot::GoModules::Version.new("1.3.0"))
        expect(Dependabot::SharedHelpers).not_to have_received(:run_shell_command)
          .with(a_string_starting_with("go list -m -json "), anything)
      end
    end

    it "does not add timestamp requests to security selection" do
      expect(finder.lowest_security_fix_version).to eq(Dependabot::GoModules::Version.new("1.1.0"))
      expect(Dependabot::SharedHelpers).not_to have_received(:run_shell_command)
        .with(a_string_starting_with("go list -m -json "), anything)
    end

    ["{}", '{"Time":null}'].each do |body|
      context "with an absent timestamp #{body}" do
        let(:newest_response) { body }

        it "clears a previous date on the same cached object and permits the update" do
          newest = finder.available_versions.first
          newest.released_at = Time.utc(2024, 6, 14)

          expect(finder.latest_version).to eq(Dependabot::GoModules::Version.new("1.3.0"))
          expect(finder.available_versions.first).to equal(newest)
          expect(newest.released_at).to be_nil
          expect(Dependabot::SharedHelpers).not_to have_received(:run_shell_command)
            .with(middle_query, fingerprint: timestamp_fingerprint)
        end
      end
    end

    context "when the timestamp command fails" do
      before do
        failure = Dependabot::SharedHelpers::HelperSubprocessFailed.new(message: "network failure", error_context: {})
        allow(Dependabot::SharedHelpers).to receive(:run_shell_command)
          .with(newest_query, fingerprint: timestamp_fingerprint).and_raise(failure)
        allow(Dependabot.logger).to receive(:info).and_call_original
      end

      it "retains the existing date and logs the ordinary failure" do
        newest = finder.available_versions.first
        newest.released_at = Time.utc(2024, 6, 14)

        expect(finder.latest_version).to eq(Dependabot::GoModules::Version.new("1.3.0"))
        expect(newest.released_at).to eq(Time.utc(2024, 6, 14))
        expect(Dependabot.logger).to have_received(:info)
          .with("Error while fetching release date info: network failure")
      end
    end

    [
      '{"do-not-echo-this":',
      "null",
      '{"Time":false}',
      '{"Time":"do-not-echo-this"}',
      '{"Time":"2024-06-14T00:00:00Z","Versions":[null]}'
    ].each do |body|
      context "with malformed timestamp output #{body}" do
        let(:newest_response) { body }

        it "propagates the error without altering cached metadata or selecting another candidate" do
          newest = finder.available_versions.first
          newest.released_at = Time.utc(2024, 6, 14)

          expect { finder.latest_version }.to raise_error(Dependabot::GoModules::ModuleInfo::InvalidOutput)
          expect(newest.released_at).to eq(Time.utc(2024, 6, 14))
          expect(Dependabot::SharedHelpers).not_to have_received(:run_shell_command)
            .with(middle_query, fingerprint: timestamp_fingerprint)
        end
      end
    end

    context "when every candidate remains in cooldown" do
      let(:middle_response) { newest_response }
      let(:oldest_response) { newest_response }

      it "preserves repeated date queries when the selected version remains nil" do
        2.times { expect(finder.latest_version).to be_nil }

        expect(Dependabot::SharedHelpers).to have_received(:run_shell_command)
          .with(version_query, fingerprint: version_fingerprint).once
        expect(Dependabot::SharedHelpers).to have_received(:run_shell_command)
          .with(newest_query, fingerprint: timestamp_fingerprint).twice
        expect(Dependabot::SharedHelpers).to have_received(:run_shell_command)
          .with(middle_query, fingerprint: timestamp_fingerprint).twice
        expect(Dependabot::SharedHelpers).to have_received(:run_shell_command)
          .with(oldest_query, fingerprint: timestamp_fingerprint).twice
      end
    end
  end

  describe "#lowest_security_fix_version" do
    subject { finder.lowest_security_fix_version }

    let(:current_version) { "1.0.0" }

    context "when on a stable release and a newer versions are available" do
      it "returns the lowest available new release" do
        expect(finder.lowest_security_fix_version).to eq(Dependabot::GoModules::Version.new("1.0.1"))
      end
    end

    context "with Dependabot-ignored versions" do
      let(:ignored_versions) { ["= 1.0.1"] }

      it "doesn't return Dependabot-ignored versions" do
        expect(finder.lowest_security_fix_version).to eq(Dependabot::GoModules::Version.new("1.0.5"))
      end
    end

    context "with a go.mod vulnerable version" do
      let(:security_advisories) do
        [
          Dependabot::SecurityAdvisory.new(
            dependency_name: dependency_name,
            package_manager: "go_modules",
            vulnerable_versions: ["<= 1.0.5"]
          )
        ]
      end

      it "doesn't return to the vulnerable version" do
        expect(finder.lowest_security_fix_version).to eq(Dependabot::GoModules::Version.new("1.0.6"))
      end
    end

    context "with a Git pseudo-version and releases available" do
      let(:dependency_version) { "0.0.0-20201021035429-f5854403a974" }
      let(:dependency_name) { "golang.org/x/net" }

      let(:security_advisories) do
        [
          Dependabot::SecurityAdvisory.new(
            dependency_name: "golang.org/x/net",
            package_manager: "go_modules",
            vulnerable_versions: ["< 0.6.0"]
          )
        ]
      end

      it "picks the minimum version that isn't vulnerable" do
        expect(finder.lowest_security_fix_version).to eq(Dependabot::GoModules::Version.new("0.6.0"))
      end

      context "with a pseudo-version as the patched version" do
        let(:security_advisories) do
          [
            Dependabot::SecurityAdvisory.new(
              dependency_name: "golang.org/x/net",
              package_manager: "go_modules",
              safe_versions: ["0.0.0-20220906165146-f3363e06e74c"]
            )
          ]
        end

        it "picks the minimum version that is safe" do
          expect(finder.lowest_security_fix_version).to eq(Dependabot::GoModules::Version.new("0.1.0"))
        end
      end
    end

    context "when on a pre-release" do
      let(:dependency_version) { "1.2.0-pre1" }

      it "returns newest pre-release" do
        expect(finder.lowest_security_fix_version).to eq(Dependabot::GoModules::Version.new("1.2.0-pre2"))
      end
    end

    context "when on a stable release and a newer prerelease is available" do
      let(:current_version) { "1.1.0" }

      it "doesn't return pre-release" do
        expect(finder.lowest_security_fix_version).not_to eq(Dependabot::GoModules::Version.new("1.2.0-pre2"))
      end
    end

    context "when the advisory boundary is a pseudo-version not listed by the Go proxy" do
      # The Go proxy only indexes tagged releases. When an advisory references a pseudo-version
      # as the fix boundary (e.g. "< 1.2.1-0.20260320110106-0b84568fffcc"), the pseudo-version
      # will not appear in the proxy's version list. In this case all proxy versions are still
      # vulnerable, and Dependabot must surface the pseudo-version from the advisory itself.
      let(:fix_pseudo_version) { "1.2.1-0.20260320110106-0b84568fffcc" }
      let(:security_advisories) do
        [
          Dependabot::SecurityAdvisory.new(
            dependency_name: dependency_name,
            package_manager: "go_modules",
            vulnerable_versions: ["< #{fix_pseudo_version}"]
          )
        ]
      end

      it "returns the pseudo-version from the advisory boundary as the fix version" do
        expect(finder.lowest_security_fix_version)
          .to eq(Dependabot::GoModules::Version.new(fix_pseudo_version))
      end
    end

    context "when the advisory boundary is a pseudo-version in a multi-constraint range" do
      let(:fix_pseudo_version) { "1.2.1-0.20260320110106-0b84568fffcc" }
      let(:security_advisories) do
        [
          Dependabot::SecurityAdvisory.new(
            dependency_name: dependency_name,
            package_manager: "go_modules",
            vulnerable_versions: [">= 0, < #{fix_pseudo_version}"]
          )
        ]
      end

      it "returns the pseudo-version from the upper bound as the fix version" do
        expect(finder.lowest_security_fix_version)
          .to eq(Dependabot::GoModules::Version.new(fix_pseudo_version))
      end
    end
  end
end
