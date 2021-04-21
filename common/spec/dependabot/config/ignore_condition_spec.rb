# frozen_string_literal: true

RSpec.describe Dependabot::Config::IgnoreCondition do
  let(:dependency_name) { "test" }
  let(:versions) { nil }
  let(:update_types) { nil }
  let(:ignore_condition) do
    described_class.new(
      dependency_name: dependency_name,
      versions: versions,
      update_types: update_types
    )
  end

  describe "#versions" do
    subject(:ignored_versions) { ignore_condition.ignored_versions(dependency) }
    let(:dependency) do
      Dependabot::Dependency.new(
        name: dependency_name,
        requirements: [],
        package_manager: "npm_and_yarn",
        version: "1.2.3"
      )
    end

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

    context "with static ignored versions" do
      let(:versions) { [">= 2.0.0"] }
      it "returns the versions" do
        expect(ignored_versions).to eq([">= 2.0.0"])
      end

      it "ignores expected versions" do
        expect_allowed("1.0.0", "1.1.0", "1.1.1")
        expect_ignored("2.0", "2.0.0")
      end
    end

    context "with patch versions ignored" do
      let(:update_types) { [:ignore_patch_versions] }

      it "ignores expected versions" do
        expect_allowed("1.3.0", "2.0.0")
        expect_ignored("1.2.3", "1.2.4", "1.2.5")
      end
    end

    context "with minor versions ignored" do
      let(:update_types) { [:ignore_minor_versions] }

      it "ignores expected versions" do
        expect_allowed("2.0.0")
        expect_ignored("1.2.3", "1.2.4", "1.3.0")
      end
    end

    context "with major versions ignored" do
      let(:update_types) { [:ignore_major_versions] }

      it "ignores expected versions" do
        expect_ignored("1.2.3", "1.2.4", "1.3.0", "2.0.0")
      end
    end
  end
end
