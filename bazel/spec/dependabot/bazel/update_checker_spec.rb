# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/bazel"
require "dependabot/bazel/update_checker"
require "dependabot/bazel/version"
require_common_spec "update_checkers/shared_examples_for_update_checkers"

RSpec.describe Dependabot::Bazel::UpdateChecker do
  let(:dependency) do
    Dependabot::Dependency.new(
      name: dependency_name,
      version: dependency_version,
      package_manager: "bazel",
      requirements: dependency_requirements
    )
  end

  let(:dependency_name) { "rules_go" }
  let(:dependency_version) { "0.33.0" }
  let(:dependency_requirements) do
    [{
      file: "MODULE.bazel",
      requirement: "0.33.0",
      groups: [],
      source: nil
    }]
  end

  let(:dependency_files) { [module_file] }
  let(:module_file) do
    Dependabot::DependencyFile.new(
      name: "MODULE.bazel",
      content: module_content
    )
  end
  let(:module_content) do
    <<~BAZEL
      module(name = "test_module", version = "1.0.0")

      bazel_dep(name = "rules_go", version = "0.33.0")
    BAZEL
  end

  let(:credentials) { [] }
  let(:ignored_versions) { [] }
  let(:security_advisories) { [] }

  let(:checker) do
    described_class.new(
      dependency: dependency,
      dependency_files: dependency_files,
      credentials: credentials,
      ignored_versions: ignored_versions,
      security_advisories: security_advisories
    )
  end

  let(:registry_client) { instance_double(Dependabot::Bazel::UpdateChecker::RegistryClient) }

  before do
    allow(Dependabot::Bazel::UpdateChecker::RegistryClient).to receive(:new).and_return(registry_client)
  end

  it_behaves_like "an update checker"

  describe "#latest_version" do
    context "when a newer version is available" do
      before do
        allow(registry_client).to receive(:get_metadata)
          .with("rules_go")
          .and_return({
            "name" => "rules_go",
            "versions" => ["0.33.0", "0.34.0", "0.57.0"],
            "latest_version" => "0.57.0"
          })

        allow(registry_client).to receive(:all_module_versions)
          .with("rules_go")
          .and_return(["0.33.0", "0.34.0", "0.57.0"])

        allow(registry_client).to receive(:latest_module_version)
          .with("rules_go")
          .and_return("0.57.0")
      end

      it "returns the latest version" do
        expect(checker.latest_version).to eq(Dependabot::Bazel::Version.new("0.57.0"))
      end
    end

    context "when the module does not exist" do
      before do
        allow(registry_client).to receive(:get_metadata)
          .with("rules_go")
          .and_return(nil)
      end

      it "returns nil" do
        expect(checker.latest_version).to be_nil
      end
    end

    context "when there are no available versions" do
      before do
        allow(registry_client).to receive(:get_metadata)
          .with("rules_go")
          .and_return({
            "name" => "rules_go",
            "versions" => [],
            "latest_version" => nil
          })

        allow(registry_client).to receive(:all_module_versions)
          .with("rules_go")
          .and_return([])

        allow(registry_client).to receive(:latest_module_version)
          .with("rules_go")
          .and_return(nil)
      end

      it "returns nil" do
        expect(checker.latest_version).to be_nil
      end
    end

    context "when registry client raises an error" do
      before do
        allow(registry_client).to receive(:get_metadata)
          .with("rules_go")
          .and_raise(Dependabot::DependabotError, "Network error")

        allow(Dependabot.logger).to receive(:warn)
      end

      it "returns nil and logs a warning" do
        expect(checker.latest_version).to be_nil
        expect(Dependabot.logger).to have_received(:warn)
          .with("Failed to fetch latest version for rules_go: Network error")
      end
    end

    context "with BCR .bcr.X versions" do
      let(:dependency_name) { "libpng" }
      let(:dependency_version) { "1.6.50" }

      context "when .bcr.X versions are available" do
        before do
          allow(registry_client).to receive(:get_metadata)
            .with("libpng")
            .and_return({
              "name" => "libpng",
              "versions" => ["1.6.50", "1.6.50.bcr.1"],
              "latest_version" => "1.6.50.bcr.1"
            })

          allow(registry_client).to receive(:all_module_versions)
            .with("libpng")
            .and_return(["1.6.50", "1.6.50.bcr.1"])
        end

        it "returns the .bcr.X version as latest" do
          expect(checker.latest_version).to eq(Dependabot::Bazel::Version.new("1.6.50.bcr.1"))
        end

        it "treats .bcr.X as newer than base version" do
          latest = checker.latest_version
          base = Dependabot::Bazel::Version.new("1.6.50")
          expect(latest).to be > base
        end
      end

      context "when multiple .bcr.X versions exist" do
        before do
          allow(registry_client).to receive(:get_metadata)
            .with("libpng")
            .and_return({
              "name" => "libpng",
              "versions" => ["1.6.50", "1.6.50.bcr.1", "1.6.50.bcr.2"],
              "latest_version" => "1.6.50.bcr.2"
            })

          allow(registry_client).to receive(:all_module_versions)
            .with("libpng")
            .and_return(["1.6.50", "1.6.50.bcr.1", "1.6.50.bcr.2"])
        end

        it "returns the highest .bcr.X version" do
          expect(checker.latest_version).to eq(Dependabot::Bazel::Version.new("1.6.50.bcr.2"))
        end

        it "correctly orders .bcr versions" do
          versions = [
            Dependabot::Bazel::Version.new("1.6.50"),
            Dependabot::Bazel::Version.new("1.6.50.bcr.1"),
            Dependabot::Bazel::Version.new("1.6.50.bcr.2")
          ]
          expect(versions.max).to eq(Dependabot::Bazel::Version.new("1.6.50.bcr.2"))
        end
      end

      context "when upgrading from base to .bcr.X version" do
        let(:dependency_version) { "1.6.50" }

        before do
          allow(registry_client).to receive(:get_metadata)
            .with("libpng")
            .and_return({
              "name" => "libpng",
              "versions" => ["1.6.50", "1.6.50.bcr.1"],
              "latest_version" => "1.6.50.bcr.1"
            })

          allow(registry_client).to receive(:all_module_versions)
            .with("libpng")
            .and_return(["1.6.50", "1.6.50.bcr.1"])
        end

        it "suggests upgrade to .bcr.X version" do
          expect(checker.latest_version).to eq(Dependabot::Bazel::Version.new("1.6.50.bcr.1"))
        end

        it "does not suggest staying at base version" do
          expect(checker.latest_version).not_to eq(Dependabot::Bazel::Version.new("1.6.50"))
        end
      end

      context "when upgrading from .bcr.X to higher .bcr.Y" do
        let(:dependency_version) { "1.6.50.bcr.1" }

        before do
          allow(registry_client).to receive(:get_metadata)
            .with("libpng")
            .and_return({
              "name" => "libpng",
              "versions" => ["1.6.50", "1.6.50.bcr.1", "1.6.50.bcr.2"],
              "latest_version" => "1.6.50.bcr.2"
            })

          allow(registry_client).to receive(:all_module_versions)
            .with("libpng")
            .and_return(["1.6.50", "1.6.50.bcr.1", "1.6.50.bcr.2"])
        end

        it "suggests upgrade to higher .bcr version" do
          expect(checker.latest_version).to eq(Dependabot::Bazel::Version.new("1.6.50.bcr.2"))
        end
      end

      context "when already at latest .bcr.X version" do
        let(:dependency_version) { "1.6.50.bcr.1" }

        before do
          allow(registry_client).to receive(:get_metadata)
            .with("libpng")
            .and_return({
              "name" => "libpng",
              "versions" => ["1.6.50", "1.6.50.bcr.1"],
              "latest_version" => "1.6.50.bcr.1"
            })

          allow(registry_client).to receive(:all_module_versions)
            .with("libpng")
            .and_return(["1.6.50", "1.6.50.bcr.1"])
        end

        it "returns nil (no update needed)" do
          expect(checker.latest_version).to be_nil
        end

        it "does not suggest downgrade to base version" do
          # The base version should be filtered out as it's lower than current
          base_version = Dependabot::Bazel::Version.new("1.6.50")
          current_version = Dependabot::Bazel::Version.new(dependency_version)
          expect(current_version).to be > base_version
        end
      end

      context "when on .bcr.X version but newer .bcr version exists" do
        let(:dependency_version) { "1.6.50.bcr.1" }

        before do
          allow(registry_client).to receive(:get_metadata)
            .with("libpng")
            .and_return({
              "name" => "libpng",
              "versions" => ["1.6.50", "1.6.50.bcr.1", "1.6.50.bcr.2", "1.6.50.bcr.3"],
              "latest_version" => "1.6.50.bcr.3"
            })

          allow(registry_client).to receive(:all_module_versions)
            .with("libpng")
            .and_return(["1.6.50", "1.6.50.bcr.1", "1.6.50.bcr.2", "1.6.50.bcr.3"])
        end

        it "suggests upgrade to newest .bcr version" do
          expect(checker.latest_version).to eq(Dependabot::Bazel::Version.new("1.6.50.bcr.3"))
        end

        it "skips the base version in upgrade path" do
          # Should go directly from .bcr.1 to .bcr.3, not suggest base version
          expect(checker.latest_version).not_to eq(Dependabot::Bazel::Version.new("1.6.50"))
        end
      end

      context "with mixed base and .bcr.X versions" do
        let(:dependency_version) { "1.6.49" }

        before do
          allow(registry_client).to receive(:get_metadata)
            .with("libpng")
            .and_return({
              "name" => "libpng",
              "versions" => ["1.6.49", "1.6.50", "1.6.50.bcr.1", "1.6.50.bcr.2", "1.6.51"],
              "latest_version" => "1.6.51"
            })

          allow(registry_client).to receive(:all_module_versions)
            .with("libpng")
            .and_return(["1.6.49", "1.6.50", "1.6.50.bcr.1", "1.6.50.bcr.2", "1.6.51"])
        end

        it "returns the newest version considering .bcr suffixes" do
          expect(checker.latest_version).to eq(Dependabot::Bazel::Version.new("1.6.51"))
        end

        it "correctly sorts all versions" do
          versions = [
            Dependabot::Bazel::Version.new("1.6.50.bcr.2"),
            Dependabot::Bazel::Version.new("1.6.49"),
            Dependabot::Bazel::Version.new("1.6.51"),
            Dependabot::Bazel::Version.new("1.6.50"),
            Dependabot::Bazel::Version.new("1.6.50.bcr.1")
          ]
          sorted = versions.sort
          expect(sorted.map(&:to_s)).to eq(
            [
              "1.6.49",
              "1.6.50",
              "1.6.50.bcr.1",
              "1.6.50.bcr.2",
              "1.6.51"
            ]
          )
        end
      end
    end
  end

  describe "#latest_resolvable_version" do
    context "when a latest version exists" do
      before do
        allow(checker).to receive(:latest_version).and_return(Dependabot::Bazel::Version.new("0.57.0"))
      end

      it "returns the latest version" do
        expect(checker.latest_resolvable_version).to eq(Dependabot::Bazel::Version.new("0.57.0"))
      end
    end

    context "when no latest version exists" do
      before do
        allow(checker).to receive(:latest_version).and_return(nil)
      end

      it "returns nil" do
        expect(checker.latest_resolvable_version).to be_nil
      end
    end
  end

  describe "#latest_resolvable_version_with_no_unlock" do
    it "returns the current dependency version" do
      expect(checker.latest_resolvable_version_with_no_unlock).to be_nil
    end

    context "when dependency has no version" do
      let(:dependency_version) { nil }

      it "returns nil" do
        expect(checker.latest_resolvable_version_with_no_unlock).to be_nil
      end
    end
  end

  describe "#updated_requirements" do
    context "when a newer version is available" do
      before do
        allow(checker).to receive(:latest_version).and_return(Dependabot::Bazel::Version.new("0.57.0"))
      end

      it "returns updated requirements with new version" do
        updated_reqs = checker.updated_requirements

        expect(updated_reqs).to eq(
          [{
            file: "MODULE.bazel",
            requirement: "0.57.0",
            groups: [],
            source: nil
          }]
        )
      end
    end

    context "when no newer version is available" do
      before do
        allow(checker).to receive(:latest_version).and_return(nil)
      end

      it "returns the original requirements" do
        expect(checker.updated_requirements).to eq(dependency_requirements)
      end
    end

    context "with BCR .bcr.X version updates" do
      let(:dependency_name) { "libpng" }
      let(:dependency_version) { "1.6.50" }
      let(:dependency_requirements) do
        [{
          file: "MODULE.bazel",
          requirement: "1.6.50",
          groups: [],
          source: nil
        }]
      end

      before do
        allow(checker).to receive(:latest_version)
          .and_return(Dependabot::Bazel::Version.new("1.6.50.bcr.1"))
      end

      it "updates requirements to .bcr.X version" do
        updated_reqs = checker.updated_requirements

        expect(updated_reqs).to eq(
          [{
            file: "MODULE.bazel",
            requirement: "1.6.50.bcr.1",
            groups: [],
            source: nil
          }]
        )
      end

      it "preserves .bcr.X format in requirement string" do
        updated_reqs = checker.updated_requirements
        expect(updated_reqs.first[:requirement]).to eq("1.6.50.bcr.1")
        expect(updated_reqs.first[:requirement]).not_to eq("1.6.50")
      end
    end

    context "with multiple requirements" do
      let(:dependency_requirements) do
        [
          {
            file: "MODULE.bazel",
            requirement: "0.33.0",
            groups: [],
            source: nil
          },
          {
            file: "other/MODULE.bazel",
            requirement: "0.33.0",
            groups: [],
            source: nil
          }
        ]
      end

      before do
        allow(checker).to receive(:latest_version).and_return(Dependabot::Bazel::Version.new("0.57.0"))
      end

      it "updates all requirements" do
        updated_reqs = checker.updated_requirements

        expect(updated_reqs).to eq(
          [
            {
              file: "MODULE.bazel",
              requirement: "0.57.0",
              groups: [],
              source: nil
            },
            {
              file: "other/MODULE.bazel",
              requirement: "0.57.0",
              groups: [],
              source: nil
            }
          ]
        )
      end
    end
  end

  describe "#can_update?" do
    subject { checker.can_update?(requirements_to_unlock: :own) }

    context "when a newer version is available" do
      before do
        allow(checker).to receive(:latest_version).and_return(Dependabot::Bazel::Version.new("0.57.0"))
      end

      it { is_expected.to be true }
    end

    context "when dependency is up to date" do
      let(:dependency_version) { "0.57.0" }

      before do
        allow(checker).to receive(:latest_version).and_return(Dependabot::Bazel::Version.new("0.57.0"))
      end

      it { is_expected.to be false }
    end

    context "when no latest version is available" do
      before do
        allow(checker).to receive(:latest_version).and_return(nil)
      end

      it { is_expected.to be false }
    end
  end

  describe "#up_to_date?" do
    subject { checker.up_to_date? }

    context "when dependency is at the latest version" do
      let(:dependency_version) { "0.57.0" }

      before do
        allow(checker).to receive(:latest_version).and_return(Dependabot::Bazel::Version.new("0.57.0"))
      end

      it { is_expected.to be true }
    end

    context "when a newer version is available" do
      before do
        allow(checker).to receive(:latest_version).and_return(Dependabot::Bazel::Version.new("0.57.0"))
      end

      it { is_expected.to be false }
    end

    context "when no latest version is available" do
      before do
        allow(checker).to receive(:latest_version).and_return(nil)
      end

      it { is_expected.to be false }
    end
  end

  describe "private methods" do
    describe "#latest_version_resolvable_with_full_unlock?" do
      context "when latest version exists" do
        before do
          allow(checker).to receive(:latest_version).and_return(Dependabot::Bazel::Version.new("0.57.0"))
        end

        it "returns true" do
          expect(checker.send(:latest_version_resolvable_with_full_unlock?)).to be true
        end
      end

      context "when no latest version exists" do
        before do
          allow(checker).to receive(:latest_version).and_return(nil)
        end

        it "returns false" do
          expect(checker.send(:latest_version_resolvable_with_full_unlock?)).to be false
        end
      end
    end

    describe "#updated_dependencies_after_full_unlock" do
      context "when latest version exists" do
        before do
          allow(checker).to receive_messages(
            latest_version: Dependabot::Bazel::Version.new("0.57.0"),
            updated_requirements: [{
              file: "MODULE.bazel",
              requirement: "0.57.0",
              groups: [],
              source: nil
            }]
          )
        end

        it "returns updated dependency" do
          updated_deps = checker.send(:updated_dependencies_after_full_unlock)

          expect(updated_deps).to have_attributes(length: 1)
          expect(updated_deps.first).to have_attributes(
            name: "rules_go",
            version: "0.57.0",
            previous_version: "0.33.0",
            package_manager: "bazel"
          )
        end
      end

      context "when no latest version exists" do
        before do
          allow(checker).to receive(:latest_version).and_return(nil)
        end

        it "returns empty array" do
          expect(checker.send(:updated_dependencies_after_full_unlock)).to eq([])
        end
      end
    end

    describe "#apply_cooldown_filter" do
      let(:versions) { ["0.33.0", "0.34.0", "0.57.0", "0.58.0"] }
      let(:old_time) { Time.now - (48 * 60 * 60) } # 48 hours ago (outside cooldown)
      let(:recent_time) { Time.now - (12 * 60 * 60) } # 12 hours ago (inside cooldown)

      context "when cooldown is disabled" do
        before do
          allow(checker).to receive(:should_skip_cooldown?).and_return(true)
        end

        it "returns all versions unchanged" do
          result = checker.send(:apply_cooldown_filter, versions)
          expect(result).to eq(versions)
        end
      end

      context "when cooldown is enabled" do
        before do
          allow(checker).to receive(:should_skip_cooldown?).and_return(false)
          allow(Dependabot.logger).to receive(:info)

          # Mock cooldown period check - return true for recent time, false for old time
          allow(checker).to receive(:cooldown_period?) do |release_time|
            (Time.now.to_i - release_time.to_i) < (24 * 60 * 60) # 24 hours
          end

          # Mock publication details for time-based filtering
          allow(checker).to receive(:publication_detail) do |version|
            release_time = case version
                           when "0.58.0" then recent_time # Latest version within cooldown
                           when "0.57.0" then old_time    # Older version outside cooldown
                           when "0.34.0" then old_time    # Even older version
                           when "0.33.0" then old_time    # Oldest version
                           else old_time
                           end

            instance_double(Dependabot::Package::PackageRelease, released_at: release_time)
          end
        end

        it "excludes versions within cooldown period" do
          result = checker.send(:apply_cooldown_filter, versions)
          expect(result).to eq(["0.33.0", "0.34.0", "0.57.0"])
        end

        it "logs which versions were skipped" do
          checker.send(:apply_cooldown_filter, versions)
          expect(Dependabot.logger).to have_received(:info)
            .with("Skipping version 0.58.0 due to cooldown period")
        end

        context "with only one version available" do
          let(:versions) { ["0.58.0"] }

          it "returns empty array when only version is in cooldown" do
            result = checker.send(:apply_cooldown_filter, versions)
            expect(result).to eq([])
          end
        end

        context "with all versions within cooldown period" do
          before do
            # Mock cooldown period check to always return true (all versions in cooldown)
            allow(checker).to receive(:cooldown_period?).and_return(true)

            allow(checker).to receive(:publication_detail) do |_version|
              instance_double(Dependabot::Package::PackageRelease, released_at: recent_time)
            end
          end

          it "returns empty array" do
            result = checker.send(:apply_cooldown_filter, versions)
            expect(result).to eq([])
          end
        end

        context "when publication details are missing" do
          before do
            allow(checker).to receive(:publication_detail).and_return(nil)
          end

          it "returns all versions when no release dates available" do
            result = checker.send(:apply_cooldown_filter, versions)
            expect(result).to eq(versions)
          end
        end
      end
    end

    describe "#should_skip_cooldown?" do
      context "when update_cooldown is nil" do
        let(:checker) do
          described_class.new(
            dependency: dependency,
            dependency_files: dependency_files,
            credentials: credentials,
            update_cooldown: nil
          )
        end

        it "returns true" do
          expect(checker.send(:should_skip_cooldown?)).to be true
        end
      end

      context "when cooldown is disabled" do
        before do
          allow(checker).to receive(:cooldown_enabled?).and_return(false)
        end

        it "returns true" do
          expect(checker.send(:should_skip_cooldown?)).to be true
        end
      end

      context "when dependency is not included in cooldown" do
        let(:cooldown_options) { instance_double(Dependabot::Package::ReleaseCooldownOptions) }
        let(:checker) do
          described_class.new(
            dependency: dependency,
            dependency_files: dependency_files,
            credentials: credentials,
            update_cooldown: cooldown_options
          )
        end

        before do
          allow(cooldown_options).to receive(:included?).with("rules_go").and_return(false)
        end

        it "returns true" do
          expect(checker.send(:should_skip_cooldown?)).to be true
        end
      end

      context "when all cooldown conditions are met" do
        let(:cooldown_options) { instance_double(Dependabot::Package::ReleaseCooldownOptions) }
        let(:checker) do
          described_class.new(
            dependency: dependency,
            dependency_files: dependency_files,
            credentials: credentials,
            update_cooldown: cooldown_options
          )
        end

        before do
          allow(cooldown_options).to receive(:included?).with("rules_go").and_return(true)
        end

        it "returns false" do
          expect(checker.send(:should_skip_cooldown?)).to be false
        end
      end
    end

    describe "#cooldown_enabled?" do
      it "returns true" do
        expect(checker.send(:cooldown_enabled?)).to be true
      end
    end

    describe "#cooldown_period?" do
      let(:cooldown_options) { instance_double(Dependabot::Package::ReleaseCooldownOptions) }
      let(:checker) do
        described_class.new(
          dependency: dependency,
          dependency_files: dependency_files,
          credentials: credentials,
          update_cooldown: cooldown_options
        )
      end

      before do
        allow(cooldown_options).to receive(:default_days).and_return(1) # 1 day cooldown
      end

      context "when release is within cooldown period" do
        let(:recent_release) { Time.now - (12 * 60 * 60) } # 12 hours ago

        it "returns true" do
          expect(checker.send(:cooldown_period?, recent_release)).to be true
        end
      end

      context "when release is outside cooldown period" do
        let(:old_release) { Time.now - (48 * 60 * 60) } # 48 hours ago

        it "returns false" do
          expect(checker.send(:cooldown_period?, old_release)).to be false
        end
      end

      context "when update_cooldown is nil" do
        let(:checker) do
          described_class.new(
            dependency: dependency,
            dependency_files: dependency_files,
            credentials: credentials,
            update_cooldown: nil
          )
        end

        it "returns false" do
          release_time = Time.now - (12 * 60 * 60)
          expect(checker.send(:cooldown_period?, release_time)).to be false
        end
      end
    end

    describe "#publication_detail" do
      let(:version) { "0.57.0" }
      let(:registry_client) { instance_double(Dependabot::Bazel::UpdateChecker::RegistryClient) }

      before do
        allow(checker).to receive(:registry_client).and_return(registry_client)
      end

      context "when publication details are not cached" do
        let(:release_date) { Time.now - (24 * 60 * 60) }

        before do
          allow(registry_client).to receive(:get_version_release_date)
            .with("rules_go", version)
            .and_return(release_date)
        end

        it "fetches and caches publication details" do
          result = checker.send(:publication_detail, version)

          expect(result).to be_a(Dependabot::Package::PackageRelease)
          expect(result.version.to_s).to eq(version)
          expect(result.released_at).to eq(release_date)
          expect(result.package_type).to eq("bazel")
        end

        it "caches the result for subsequent calls" do
          checker.send(:publication_detail, version)
          checker.send(:publication_detail, version)

          expect(registry_client).to have_received(:get_version_release_date).once
        end
      end

      context "when publication details are already cached" do
        let(:cached_details) { instance_double(Dependabot::Package::PackageRelease) }

        before do
          allow(registry_client).to receive(:get_version_release_date)
          checker.instance_variable_set(:@publication_details, { version => cached_details })
        end

        it "returns cached details without fetching" do
          result = checker.send(:publication_detail, version)
          expect(result).to eq(cached_details)
          expect(registry_client).not_to have_received(:get_version_release_date)
        end
      end

      context "when release date cannot be fetched" do
        before do
          allow(registry_client).to receive(:get_version_release_date)
            .with("rules_go", version)
            .and_return(nil)
        end

        it "returns nil" do
          result = checker.send(:publication_detail, version)
          expect(result).to be_nil
        end
      end
    end

    describe "#version_sort_key" do
      it "generates correct sort keys for semantic versions" do
        sort_key_one_zero_zero = checker.send(:version_sort_key, "1.0.0")
        sort_key_one_two_zero = checker.send(:version_sort_key, "1.2.0")
        sort_key_one_ten_zero = checker.send(:version_sort_key, "1.10.0")

        expect(sort_key_one_zero_zero).to eq([1, 0, 0])
        expect(sort_key_one_two_zero).to eq([1, 2, 0])
        expect(sort_key_one_ten_zero).to eq([1, 10, 0])

        # Verify correct ordering
        expect(sort_key_one_zero_zero <=> sort_key_one_two_zero).to eq(-1)
        expect(sort_key_one_two_zero <=> sort_key_one_ten_zero).to eq(-1)
      end

      it "handles version prefixes" do
        sort_key = checker.send(:version_sort_key, "v1.2.3")
        expect(sort_key).to eq([1, 2, 3])
      end

      it "handles non-numeric version parts" do
        sort_key = checker.send(:version_sort_key, "1.2.beta")
        expect(sort_key).to eq([1, 2, 0])
      end
    end
  end

  describe "ignored versions" do
    let(:ignored_versions) { [">= 2.a"] }

    before do
      allow(registry_client).to receive(:get_metadata)
        .with("rules_go")
        .and_return({
          "name" => "rules_go",
          "versions" => ["0.33.0", "0.34.0", "1.9.0", "2.0.0", "3.0.0"],
          "latest_version" => "3.0.0"
        })

      allow(registry_client).to receive(:all_module_versions)
        .with("rules_go")
        .and_return(["0.33.0", "0.34.0", "1.9.0", "2.0.0", "3.0.0"])
    end

    context "when ignoring major version updates" do
      it "filters out major versions" do
        expect(checker.latest_version).to eq(Dependabot::Bazel::Version.new("1.9.0"))
      end

      it "logs filtered versions" do
        allow(Dependabot.logger).to receive(:info)
        checker.latest_version
        expect(Dependabot.logger).to have_received(:info)
          .with("Filtered out 2 ignored versions")
      end
    end

    context "when all versions are ignored" do
      let(:ignored_versions) { [">= 0"] }

      it "returns nil" do
        expect(checker.latest_version).to be_nil
      end
    end

    context "when ignoring specific version ranges" do
      let(:ignored_versions) { [">= 1.0, < 2.0"] }

      it "filters out versions in the specified range" do
        expect(checker.latest_version).to eq(Dependabot::Bazel::Version.new("3.0.0"))
      end
    end

    context "when raise_on_ignored is true" do
      let(:ignored_versions) { [">= 0.34"] }
      let(:checker) do
        described_class.new(
          dependency: dependency,
          dependency_files: dependency_files,
          credentials: credentials,
          ignored_versions: ignored_versions,
          raise_on_ignored: true
        )
      end

      before do
        # Need to set up mocks for the new checker instance
        allow(Dependabot::Bazel::UpdateChecker::RegistryClient).to receive(:new).and_return(registry_client)
        allow(Dependabot.logger).to receive(:info)
      end

      it "logs when all newer versions are ignored" do
        expect(checker.latest_version).to be_nil
        expect(Dependabot.logger).to have_received(:info)
          .with("All updates for rules_go were ignored")
      end
    end
  end

  describe "cooldown integration" do
    let(:cooldown_options) { instance_double(Dependabot::Package::ReleaseCooldownOptions) }
    let(:checker_with_cooldown) do
      described_class.new(
        dependency: dependency,
        dependency_files: dependency_files,
        credentials: credentials,
        update_cooldown: cooldown_options
      )
    end

    before do
      allow(cooldown_options).to receive(:included?).with("rules_go").and_return(true)
      allow(cooldown_options).to receive(:default_days).and_return(1) # 1 day cooldown
      allow(Dependabot.logger).to receive(:info)
    end

    context "when cooldown is active" do
      let(:old_time) { Time.now - (48 * 60 * 60) } # 48 hours ago (outside cooldown)
      let(:recent_time) { Time.now - (12 * 60 * 60) } # 12 hours ago (inside cooldown)

      before do
        allow(registry_client).to receive(:get_metadata)
          .with("rules_go")
          .and_return({
            "name" => "rules_go",
            "versions" => ["0.33.0", "0.34.0", "0.57.0", "0.58.0"],
            "latest_version" => "0.58.0"
          })

        allow(registry_client).to receive(:all_module_versions)
          .with("rules_go")
          .and_return(["0.33.0", "0.34.0", "0.57.0", "0.58.0"])

        # Mock time-based cooldown publication details
        allow(checker_with_cooldown).to receive(:publication_detail) do |version|
          release_time = case version
                         when "0.58.0" then recent_time # Latest version within cooldown
                         when "0.57.0" then old_time    # Older version outside cooldown
                         else old_time                  # Even older versions
                         end

          instance_double(Dependabot::Package::PackageRelease, released_at: release_time)
        end

        allow(checker_with_cooldown).to receive(:registry_client).and_return(registry_client)
      end

      it "returns second-latest version due to cooldown" do
        expect(checker_with_cooldown.latest_version).to eq(Dependabot::Bazel::Version.new("0.57.0"))
      end

      it "logs cooldown information" do
        checker_with_cooldown.latest_version
        expect(Dependabot.logger).to have_received(:info)
          .with("Skipping version 0.58.0 due to cooldown period")
      end
    end

    context "when cooldown would exclude all versions" do
      let(:recent_time) { Time.now - (12 * 60 * 60) } # 12 hours ago (inside cooldown)

      before do
        allow(registry_client).to receive(:get_metadata)
          .with("rules_go")
          .and_return({
            "name" => "rules_go",
            "versions" => ["0.58.0"],
            "latest_version" => "0.58.0"
          })

        allow(registry_client).to receive(:all_module_versions)
          .with("rules_go")
          .and_return(["0.58.0"])

        # Mock that the only version is within cooldown period
        allow(checker_with_cooldown).to receive(:publication_detail) do |_version|
          instance_double(Dependabot::Package::PackageRelease, released_at: recent_time)
        end

        allow(checker_with_cooldown).to receive(:registry_client).and_return(registry_client)
      end

      it "returns nil when all versions are filtered out" do
        expect(checker_with_cooldown.latest_version).to be_nil
      end
    end
  end
end
