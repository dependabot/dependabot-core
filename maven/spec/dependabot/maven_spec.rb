# frozen_string_literal: true

require "spec_helper"
require "dependabot/maven"
require_common_spec "shared_examples_for_autoloading"

RSpec.describe Dependabot::Maven do
  it_behaves_like "it registers the required classes", "maven"

  describe "Dependency#display_name" do
    subject(:display_name) do
      Dependabot::Dependency.new(**dependency_args).display_name
    end

    let(:dependency_args) do
      { name: name, requirements: [], package_manager: "maven" }
    end

    context "normal dependency" do
      let(:name) { "group.com:dep" }

      it { is_expected.to eq("dep") }
    end

    context "dependency with classifier" do
      let(:name) { "group.com:dep:mule-plugin" }

      it { is_expected.to eq("dep") }
    end

    context "with a special-cased name" do
      let(:name) { "group.com:bom" }

      it { is_expected.to eq("group.com:bom") }
    end
  end
end
