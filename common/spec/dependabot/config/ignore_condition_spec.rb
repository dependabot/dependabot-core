# frozen_string_literal: true

require "dependabot/config/ignore_condition"
require "dependabot/dependency"
require "spec_helper"

RSpec.describe Dependabot::Config::IgnoreCondition do
  let(:dependency_name) { "test" }
  let(:dependency_version) { "1.2.3" }
  let(:ignore_condition) { described_class.new(dependency_name: dependency_name) }
  let(:security_updates_only) { false }
  let(:package_manager) { "dummy" }

  describe "#ignored_versions" do
    subject(:ignored_versions) { ignore_condition.ignored_versions(dependency, security_updates_only) }
    let(:dependency) do
      Dependabot::Dependency.new(
        name: dependency_name,
        requirements: [],
        package_manager: package_manager,
        version: dependency_version
      )
    end

    # Test helpers for reasoning about specific semver versions:
    def expect_allowed(versions)
      reqs = ignored_versions.map { |v| Gem::Requirement.new(v.split(",").map(&:strip)) }
      versions.each do |v|
        version = Dependabot::Utils.version_class_for_package_manager(package_manager).new(v)
        ignored = reqs.any? { |req| req.satisfied_by?(version) }
        expect(ignored).to eq(false), "Expected #{v} to be allowed, but was ignored"
      end
    end

    def expect_ignored(versions)
      reqs = ignored_versions.map { |v| Gem::Requirement.new(v.split(",").map(&:strip)) }
      versions.each do |v|
        version = Dependabot::Version.new(v)
        ignored = reqs.any? { |req| req.satisfied_by?(version) }
        expect(ignored).to eq(true), "Expected #{v} to be ignored, but was allowed"
      end
    end

    context "without versions or update_types" do
      let(:ignore_condition) { described_class.new(dependency_name: dependency_name) }

      it "ignores all versions" do
        expect(ignored_versions).to eq([">= 0"])
      end
    end

    context "with versions" do
      let(:ignore_condition) { described_class.new(dependency_name: dependency_name, versions: [">= 2.0.0"]) }

      it "returns the static versions" do
        expect(ignored_versions).to eq([">= 2.0.0"])
      end

      it "ignores expected versions" do
        expect_allowed(["1.0.0", "1.1.0", "1.1.1"])
        expect_ignored(["2.0", "2.0.0"])
      end

      context "with security_updates_only" do
        let(:security_updates_only) { true }

        it "returns the static versions" do
          expect(ignored_versions).to eq([">= 2.0.0"])
        end
      end
    end

    context "with update_types" do
      let(:ignore_condition) { described_class.new(dependency_name: dependency_name, update_types: update_types) }
      let(:dependency_version) { "1.2.3" }
      let(:patch_upgrades) { %w(1.2.4 1.2.5 1.2.4-rc0) }
      let(:minor_upgrades) { %w(1.3 1.3.0 1.4 1.4.0) }
      let(:major_upgrades) { %w(2 2.0 2.0.0 3 3.0 3.0.0) }

      context "with ignore_patch_versions" do
        let(:update_types) { ["version-update:semver-patch"] }

        it "ignores expected versions" do
          expect_allowed(minor_upgrades + major_upgrades)
          expect_ignored(patch_upgrades)
          expect_allowed([dependency_version])
        end

        it "returns the expected range" do
          expect(ignored_versions).to eq(["> 1.2.3, < 1.3"])
        end
      end

      context "with ignore_minor_versions" do
        let(:update_types) { ["version-update:semver-minor"] }

        it "ignores expected versions" do
          expect_allowed(patch_upgrades + major_upgrades)
          expect_ignored(minor_upgrades)
          expect_allowed([dependency_version])
        end

        it "returns the expected range" do
          expect(ignored_versions).to eq([">= 1.3.a, < 2"])
        end
      end

      context "with ignore_major_versions" do
        let(:update_types) { ["version-update:semver-major"] }

        it "ignores expected versions" do
          expect_allowed(patch_upgrades + minor_upgrades)
          expect_ignored(major_upgrades)
          expect_allowed([dependency_version])
        end

        it "returns the expected range" do
          expect(ignored_versions).to eq([">= 2.a"])
        end
      end

      context "with ignore_major_versions and ignore_patch_versions" do
        let(:update_types) { %w(version-update:semver-major version-update:semver-patch) }

        it "ignores expected versions" do
          expect_allowed(minor_upgrades)
          expect_ignored(patch_upgrades + major_upgrades)
          expect_allowed([dependency_version])
        end
      end

      context "with a 'major.minor' semver dependency" do
        let(:dependency_version) { "1.2" }

        context "with ignore_major_versions" do
          let(:update_types) { ["version-update:semver-major"] }

          it "ignores expected versions" do
            expect_allowed(patch_upgrades + minor_upgrades)
            expect_ignored(major_upgrades)
            expect_allowed([dependency_version])
          end

          it "returns the expected range" do
            expect(ignored_versions).to eq([">= 2.a"])
          end
        end

        context "with ignore_minor_versions" do
          let(:update_types) { ["version-update:semver-minor"] }

          it "ignores expected versions" do
            expect_allowed(patch_upgrades + major_upgrades)
            expect_ignored(minor_upgrades)
            expect_allowed([dependency_version])
          end

          it "returns the expected range" do
            expect(ignored_versions).to eq([">= 1.3.a, < 2"])
          end
        end

        context "with ignore_patch_versions" do
          let(:update_types) { ["version-update:semver-patch"] }

          it "ignores expected versions" do
            expect_allowed(major_upgrades + minor_upgrades)
            expect_ignored(patch_upgrades + ["1.2.1"])
            expect_allowed([dependency_version, "1.2.0"])
          end

          it "returns the expected range" do
            expect(ignored_versions).to eq(["> 1.2, < 1.3"])
          end
        end
      end

      context "with a 'major' semver dependency" do
        let(:dependency_version) { "1" }

        context "with ignore_major_versions" do
          let(:update_types) { ["version-update:semver-major"] }

          it "ignores expected versions" do
            expect_allowed(patch_upgrades + minor_upgrades)
            expect_ignored(major_upgrades)
            expect_allowed([dependency_version])
          end

          it "returns the expected range" do
            expect(ignored_versions).to eq([">= 2.a"])
          end
        end

        context "with ignore_minor_versions" do
          let(:update_types) { ["version-update:semver-minor"] }

          it "returns the expected range" do
            expect(ignored_versions).to eq([">= 1.1.a, < 2"])
          end
        end

        context "with ignore_patch_versions" do
          let(:update_types) { ["version-update:semver-patch"] }
          let(:patch_upgrades) { %w(1.0.2 1.0.5 1.0.4-rc0) }
          let(:minor_upgrades) { %w(1.1 1.2.0 1.3 1.4.0) }

          it "ignores expected versions" do
            expect_allowed(major_upgrades + minor_upgrades)
            expect_ignored(patch_upgrades)
            expect_allowed([dependency_version, "1.0.0"])
          end

          it "returns the expected range" do
            expect(ignored_versions).to eq(["> 1, < 1.1"])
          end
        end
      end

      context "with a pre-release semver version" do
        let(:dependency_version) { "1.2.3-alpha.1" }

        context "with ignore_major_versions" do
          let(:update_types) { ["version-update:semver-major"] }

          it "ignores expected versions" do
            expect_allowed(patch_upgrades + minor_upgrades)
            expect_ignored(major_upgrades)
            expect_allowed([dependency_version])
          end

          it "returns the expected range" do
            expect(ignored_versions).to eq([">= 2.a"])
          end
        end

        context "with ignore_minor_versions" do
          let(:update_types) { ["version-update:semver-minor"] }

          it "ignores expected versions" do
            expect_allowed(patch_upgrades + major_upgrades)
            expect_ignored(minor_upgrades)
            expect_allowed([dependency_version])
          end

          it "returns the expected range" do
            expect(ignored_versions).to eq([">= 1.3.a, < 2"])
          end
        end

        context "with ignore_patch_versions" do
          let(:update_types) { ["version-update:semver-patch"] }

          it "ignores expected updates" do
            expect_ignored(patch_upgrades + ["1.2.3-alpha.2", "1.2.3-alpha.1.1", "1.2.3-beta"])
            expect_allowed(minor_upgrades + major_upgrades)
            expect_allowed([dependency_version])
          end

          it "returns the expected range" do
            expect(ignored_versions).to eq(["> 1.2.3-alpha.1, < 1.3"])
          end
        end
      end

      context "with a non-semver dependency" do
        let(:dependency_version) { "Finchley.SR3" }

        context "with ignore_patch_versions" do
          let(:update_types) { ["version-update:semver-patch"] }
          it "returns the expected range" do
            expect(ignored_versions).to eq([])
          end
        end

        context "with ignore_minor_versions" do
          let(:update_types) { ["version-update:semver-minor"] }
          it "returns the expected range" do
            expect(ignored_versions).to eq([])
          end
        end

        context "with ignore_major_versions" do
          let(:update_types) { ["version-update:semver-major"] }
          it "returns the expected range" do
            expect(ignored_versions).to eq([])
          end
        end
      end

      context "with a semver dependency, but according to another package manager" do
        let(:dependency_version) { "v11.0.14" }

        context "with ignore_major_versions" do
          let(:update_types) { ["version-update:semver-major"] }

          it "ignores expected versions" do
            expect_allowed(["11"])
            expect_ignored(["17"])
            expect_allowed([dependency_version])
          end

          it "returns the expected range" do
            expect(ignored_versions).to eq([">= 12.a"])
          end
        end
      end

      context "when the dependency version isn't known" do
        let(:dependency_version) { nil }

        context "with ignore_major_versions" do
          let(:update_types) { ["version-update:semver-major"] }
          it { is_expected.to eq([]) }
        end

        context "with ignore_minor_versions" do
          let(:update_types) { ["version-update:semver-minor"] }
          it { is_expected.to eq([]) }
        end

        context "with ignore_patch_versions" do
          let(:update_types) { ["version-update:semver-patch"] }
          it { is_expected.to eq([]) }
        end
      end

      context "with security_updates_only" do
        let(:security_updates_only) { true }
        let(:update_types) { %w(version-update:semver-major version-update:semver-patch) }

        it "allows all " do
          expect_allowed(patch_upgrades + minor_upgrades + major_upgrades)
        end
      end
    end
  end
end
