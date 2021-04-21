# frozen_string_literal: true

require "dependabot/config/ignore_condition"
require "dependabot/dependency"

RSpec.describe Dependabot::Config::IgnoreCondition do
  let(:dependency_name) { "test" }
  let(:dependency_version) { "1.2.3" }
  let(:ignore_condition) { described_class.new(dependency_name: dependency_name) }

  describe "#versions" do
    subject(:ignored_versions) { ignore_condition.ignored_versions(dependency) }
    let(:dependency) do
      Dependabot::Dependency.new(
        name: dependency_name,
        requirements: [],
        package_manager: "npm_and_yarn",
        version: dependency_version
      )
    end

    # Test helpers for reasoning about specific semver versions:
    def expect_allowed(*versions)
      req = Gem::Requirement.new(ignored_versions.flat_map { |s| s.split(",").map(&:strip) })
      versions.map do |v|
        expect(req.satisfied_by?(Gem::Version.new(v))).
          to eq(false), "Expected #{v} to be allowed, but was ignored"
      end
    end

    def expect_ignored(*versions)
      req = Gem::Requirement.new(ignored_versions.flat_map { |s| s.split(",").map(&:strip) })
      versions.map do |v|
        expect(req.satisfied_by?(Gem::Version.new(v))).
          to eq(true), "Expected #{v} to be ignored, but was allowed"
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
        expect_allowed("1.0.0", "1.1.0", "1.1.1")
        expect_ignored("2.0", "2.0.0")
      end
    end

    context "with update_types" do
      let(:ignore_condition) { described_class.new(dependency_name: dependency_name, update_types: update_types) }

      context "with ignore_patch_versions" do
        let(:update_types) { [:ignore_patch_versions] }

        it "ignores expected versions" do
          expect_allowed("1.3", "1.3.0", "2.0.0")
          expect_ignored("1.2.3", "1.2.4", "1.2.5")
        end

        it "returns the expected range" do
          expect(ignored_versions).to eq([">= 1.2.a, < 1.3"])
        end

        context "and a non-semver dependency" do
          let(:dependency_version) { "Finchley.SR3" }

          it "returns the expected range" do
            expect(ignored_versions).to eq([">= Finchley.SR3.a, < Finchley.SR3.999999"])
          end
        end
      end

      context "with ignore_minor_versions" do
        let(:update_types) { [:ignore_minor_versions] }

        it "ignores expected versions" do
          expect_allowed("2.0.0")
          expect_ignored("1.2.3", "1.2.4", "1.3", "1.3.0")
        end

        it "returns the expected range" do
          expect(ignored_versions).to eq([">= 1.a, < 2"])
        end

        context "and a non-semver dependency" do
          let(:dependency_version) { "Finchley.SR3" }

          it "returns the expected range" do
            expect(ignored_versions).to eq([">= Finchley.a, < Finchley.999999"])
          end
        end
      end

      context "with ignore_major_versions" do
        let(:update_types) { [:ignore_major_versions] }

        it "ignores expected versions" do
          expect_ignored("1.2.3", "1.2.4", "1.3.0", "2.0.0")
        end

        it "returns the expected range" do
          expect(ignored_versions).to eq([">= 0"])
        end
      end

      context "with ignore_minor_versions and ignore_patch_versions" do
        let(:update_types) { %i(ignore_minor_versions ignore_patch_versions) }

        it "behaves like ignore_minor_versions" do
          expect(ignored_versions).to eq([">= 1.a, < 2"])
        end
      end
    end
  end
end
