# frozen_string_literal: true

require "dependabot/config/ignore_condition"
require "dependabot/dependency"
require "spec_helper"

RSpec.describe Dependabot::Config::IgnoreCondition do
  let(:dependency_name) { "test" }
  let(:dependency_version) { "1.2.3" }
  let(:dependency) do
    Dependabot::Dependency.new(
      name: dependency_name,
      requirements: [],
      package_manager: "npm_and_yarn",
      version: dependency_version
    )
  end

  let(:ignore_condition) { described_class.new(dependency_name: dependency_name) }
  let(:security_updates_only) { false }

  describe "#ignored_versions" do
    subject(:ignored_versions) { ignore_condition.ignored_versions(dependency, security_updates_only) }

    # Test helpers for reasoning about specific semver versions:
    def expect_allowed(versions)
      reqs = ignored_versions.map { |v| Gem::Requirement.new(v.split(",").map(&:strip)) }
      versions.each do |v|
        version = Gem::Version.new(v)
        ignored = reqs.any? { |req| req.satisfied_by?(version) }
        expect(ignored).to eq(false), "Expected #{v} to be allowed, but was ignored"
      end
    end

    def expect_ignored(versions)
      reqs = ignored_versions.map { |v| Gem::Requirement.new(v.split(",").map(&:strip)) }
      versions.each do |v|
        version = Gem::Version.new(v)
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
      let(:patch_upgrades) { %w(1.2.3 1.2.4 1.2.5 1.2.4-rc0) }
      let(:minor_upgrades) { %w(1.3 1.3.0 1.4 1.4.0) }
      let(:major_upgrades) { %w(2 2.0 2.0.0) }

      context "with ignore_patch_versions" do
        let(:update_types) { ["version-update:semver-patch"] }

        it "ignores expected versions" do
          expect_allowed(minor_upgrades + major_upgrades)
          expect_ignored(patch_upgrades)
        end

        it "returns the expected range" do
          expect(ignored_versions).to eq([">= 1.2.a, < 1.3"])
        end
      end

      context "with ignore_minor_versions" do
        let(:update_types) { ["version-update:semver-minor"] }

        it "ignores expected versions" do
          expect_allowed(patch_upgrades + major_upgrades)
          expect_ignored(minor_upgrades)
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
        end

        it "returns the expected range" do
          expect(ignored_versions).to eq([">= 2.a, < 3"])
        end
      end

      context "with ignore_major_versions and ignore_patch_versions" do
        let(:update_types) { %w(version-update:semver-major version-update:semver-patch) }

        it "ignores expected versions" do
          expect_allowed(minor_upgrades)
          expect_ignored(patch_upgrades + major_upgrades)
        end
      end

      context "with a 'major.minor' semver dependency" do
        let(:dependency_version) { "1.2" }

        context "with ignore_major_versions" do
          let(:update_types) { ["version-update:semver-major"] }

          it "ignores expected versions" do
            expect_allowed(patch_upgrades + minor_upgrades)
            expect_ignored(major_upgrades)
          end

          it "returns the expected range" do
            expect(ignored_versions).to eq([">= 2.a, < 3"])
          end
        end

        context "with ignore_minor_versions" do
          let(:update_types) { ["version-update:semver-minor"] }

          it "ignores expected versions" do
            expect_allowed(patch_upgrades + major_upgrades)
            expect_ignored(minor_upgrades)
          end

          it "returns the expected range" do
            expect(ignored_versions).to eq([">= 1.3.a, < 2"])
          end
        end

        context "with ignore_patch_versions" do
          let(:update_types) { ["version-update:semver-patch"] }

          it "ignores expected versions" do
            expect_allowed(patch_upgrades + major_upgrades + minor_upgrades)
          end

          it "returns the expected range" do
            expect(ignored_versions).to eq([])
          end
        end
      end

      context "with a 'major' semver dependency" do
        let(:dependency_version) { "1" }

        context "with ignore_major_versions" do
          let(:update_types) { ["version-update:semver-major"] }

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

        context "with ignore_patch_versions" do
          let(:update_types) { ["version-update:semver-patch"] }

          it "returns the expected range" do
            expect(ignored_versions).to eq([])
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
            expect(ignored_versions).to eq([">= Finchley.a, < Finchley.999999"])
          end
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

  describe "#ignored?" do
    let(:dependency) do
      Dependabot::Dependency.new(
        name: dependency_name,
        requirements: [],
        package_manager: "dummy",
        version: dependency_version
      )
    end
    let(:ignore_condition) { described_class.new(dependency_name: dependency_name, versions: [">= 2.0.0"]) }

    before { allow(DummyPackageManager::Version).to receive(:new).and_call_original }

    it "should ignore matching versions" do
      expect(ignore_condition.ignored?(dependency, false, "1.0.0")).to eq(false)
      expect(ignore_condition.ignored?(dependency, false, "2.0.0")).to eq(true)
      expect(ignore_condition.ignored?(dependency, false, "2.0.1")).to eq(true)
    end

    it "should use package manager's version class" do
      ignore_condition.ignored?(dependency, false, "1.0.0")

      expect(DummyPackageManager::Version).to have_received(:new)
    end

    it "should raise on unparseable versions" do
      expect { ignore_condition.ignored?(dependency, false, "foo") }.
        to raise_error(ArgumentError)
      expect(DummyPackageManager::Version).to have_received(:new)
    end
  end
end
