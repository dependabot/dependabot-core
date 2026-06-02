# typed: false
# frozen_string_literal: true

require "dependabot/config/allow_condition"
require "dependabot/dependency"
require "spec_helper"

RSpec.describe Dependabot::Config::AllowCondition do
  let(:dependency_name) { "test" }
  let(:dependency) do
    Dependabot::Dependency.new(
      name: dependency_name,
      requirements: [],
      package_manager: "dummy",
      version: "1.2.3"
    )
  end

  describe "#allowed_versions" do
    subject(:allowed_versions) do
      allow_condition.allowed_versions(dependency, security_updates_only: security_updates_only)
    end

    let(:security_updates_only) { false }

    context "without versions" do
      let(:allow_condition) { described_class.new(dependency_name: dependency_name) }

      it "returns empty" do
        expect(allowed_versions).to eq([])
      end
    end

    context "with a single band entry (comma-separated)" do
      let(:allow_condition) do
        described_class.new(dependency_name: dependency_name, versions: [">= 4.0.0, < 5.0.0"])
      end

      it "returns the band as a single entry" do
        expect(allowed_versions).to eq([">= 4.0.0, < 5.0.0"])
      end
    end

    context "with multiple OR-ed entries" do
      let(:allow_condition) do
        described_class.new(
          dependency_name: dependency_name,
          versions: [">= 4.0.0, < 5.0.0", ">= 6.0.0, < 7.0.0"]
        )
      end

      it "returns both entries (consumer OR-es them)" do
        expect(allowed_versions).to eq([">= 4.0.0, < 5.0.0", ">= 6.0.0, < 7.0.0"])
      end

      context "with security_updates_only: true" do
        let(:security_updates_only) { true }

        it "returns empty (security updates bypass allowed_versions)" do
          expect(allowed_versions).to eq([])
        end
      end
    end
  end

  describe "#dependency_name" do
    let(:allow_condition) { described_class.new(dependency_name: dependency_name) }

    it "returns the dependency name" do
      expect(allow_condition.dependency_name).to eq(dependency_name)
    end
  end

  describe "#dependency_type" do
    context "when not given" do
      let(:allow_condition) { described_class.new(dependency_name: dependency_name) }

      it "defaults to nil" do
        expect(allow_condition.dependency_type).to be_nil
      end
    end

    context "when given" do
      let(:allow_condition) do
        described_class.new(dependency_name: dependency_name, dependency_type: "production")
      end

      it "returns the dependency type" do
        expect(allow_condition.dependency_type).to eq("production")
      end
    end
  end

  describe "#versions" do
    context "with no versions given" do
      let(:allow_condition) { described_class.new(dependency_name: dependency_name) }

      it "defaults to empty array" do
        expect(allow_condition.versions).to eq([])
      end
    end

    context "with versions given" do
      let(:allow_condition) do
        described_class.new(dependency_name: dependency_name, versions: [">= 2.0.0"])
      end

      it "returns the versions" do
        expect(allow_condition.versions).to eq([">= 2.0.0"])
      end
    end
  end
end
