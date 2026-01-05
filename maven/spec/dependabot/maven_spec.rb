# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/maven"
require_common_spec "shared_examples_for_autoloading"

RSpec.describe Dependabot::Maven do
  it_behaves_like "it registers the required classes", "maven"

  describe "Dependency#production?" do
    subject(:production) do
      Dependabot::Dependency.new(**dependency_args).production?
    end

    let(:dependency_args) do
      {
        name: "group:artifact",
        requirements: [{ groups: groups, file: "pom.xml", requirement: "1.0.0", source: nil }],
        package_manager: "maven"
      }
    end

    context "with a test-scoped dependency" do
      let(:groups) { ["test"] }

      it { is_expected.to be(false) }
    end

    context "with a plugin dependency" do
      let(:groups) { ["plugin"] }

      it { is_expected.to be(false) }
    end

    context "with a compile-scoped dependency (empty groups)" do
      let(:groups) { [] }

      it { is_expected.to be(true) }
    end

    context "with a production dependency (no scope)" do
      let(:groups) { [] }

      it { is_expected.to be(true) }
    end
  end

  describe "Dependency#display_name" do
    subject(:display_name) do
      Dependabot::Dependency.new(**dependency_args).display_name
    end

    let(:dependency_args) do
      { name: name, requirements: [], package_manager: "maven" }
    end

    context "when dealing with a normal dependency" do
      let(:name) { "group.com:dep:mule-plugin" }

      it { is_expected.to eq("group.com:dep:mule-plugin") }
    end

    context "when the dependency has classifier" do
      let(:name) { "group.com:dep:mule-plugin" }

      it { is_expected.to eq("group.com:dep:mule-plugin") }
    end

    context "with a special-cased name" do
      let(:name) { "group.com:bom" }

      it { is_expected.to eq("group.com:bom") }
    end

    context "with a 100+ character name" do
      let(:name) { "com.long-domain-name-that-should-be-replaced-by-ellipsis.this-is-longer-group-id:the-longest-artifact-id" } # rubocop:disable Layout/LineLength

      it { is_expected.to eq("the-longest-artifact-id") }
    end
  end
end
