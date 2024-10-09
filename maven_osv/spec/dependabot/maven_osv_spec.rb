# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/maven_osv"
require_common_spec "shared_examples_for_autoloading"

RSpec.describe Dependabot::MavenOSV do
  it_behaves_like "it registers the required classes", "maven_osv"

  describe "Dependency#display_name" do
    subject(:display_name) do
      Dependabot::Dependency.new(**dependency_args).display_name
    end

    let(:dependency_args) do
      { name: name, requirements: [], package_manager: "maven_osv" }
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
