# frozen_string_literal: true

require "spec_helper"
require "dependabot/gradle"
require_common_spec "shared_examples_for_autoloading"

RSpec.describe Dependabot::Gradle do
  it_behaves_like "it registers the required classes", "gradle"

  describe "Dependency#display_name" do
    subject(:display_name) do
      Dependabot::Dependency.new(**dependency_args).display_name
    end

    let(:dependency_args) do
      { name: name, requirements: [], package_manager: "gradle" }
    end
    let(:name) { "group.com:dep" }

    it { is_expected.to eq("group.com:dep") }

    context "with a 100+ character name" do
      let(:name) { "com.long-domain-name-that-should-be-replaced-by-ellipsis.this-is-longer-group-id:the-longest-artifact-id" } # rubocop:disable Layout/LineLength
      it { is_expected.to eq("the-longest-artifact-id") }
    end
  end
end
