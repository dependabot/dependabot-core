# typed: strong
# frozen_string_literal: true

require "spec_helper"
require "dependabot/cargo"
require_common_spec "shared_examples_for_autoloading"

RSpec.describe Dependabot::Cargo do
  it_behaves_like "it registers the required classes", "cargo"

  describe "production check" do
    def dependency_with_groups(*groups)
      Dependabot::Dependency.new(
        name: "criterion",
        version: "0.7.0",
        package_manager: "cargo",
        requirements: groups.map do |group|
          { file: "Cargo.toml", requirement: "0.7.0", groups: [group], source: nil }
        end
      )
    end

    it "treats a dependency declared in [dependencies] as production" do
      expect(dependency_with_groups("dependencies")).to be_production
    end

    it "treats a dependency declared in [build-dependencies] as production" do
      expect(dependency_with_groups("build-dependencies")).to be_production
    end

    it "treats a dependency declared only in [dev-dependencies] as development" do
      expect(dependency_with_groups("dev-dependencies")).not_to be_production
    end

    it "treats a dependency declared in both [dependencies] and [dev-dependencies] as production" do
      expect(dependency_with_groups("dependencies", "dev-dependencies")).to be_production
    end
  end
end
