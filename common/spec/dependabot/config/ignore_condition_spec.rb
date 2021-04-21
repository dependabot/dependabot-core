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

    context "with static ignored versions" do
      let(:versions) { [">= 2.0.0"] }
      it "returns the versions" do
        expect(ignored_versions).to eq([">= 2.0.0"])
      end
    end
  end
end
