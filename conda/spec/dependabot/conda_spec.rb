# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/conda"
require_common_spec "shared_examples_for_autoloading"

RSpec.describe Dependabot::Conda do
  it_behaves_like "it registers the required classes", "conda"

  describe "production check" do
    subject(:production_check) do
      Dependabot::Dependency.production_check_for_package_manager("conda")
    end

    context "when groups is empty" do
      it "returns true" do
        expect(production_check.call([])).to be(true)
      end
    end

    context "when groups includes 'default'" do
      it "returns true" do
        expect(production_check.call(["default"])).to be(true)
      end

      it "returns true even with other groups" do
        expect(production_check.call(["dev", "default", "test"])).to be(true)
      end
    end

    context "when groups includes 'dependencies'" do
      it "returns true" do
        expect(production_check.call(["dependencies"])).to be(true)
      end

      it "returns true even with other groups" do
        expect(production_check.call(["test", "dependencies", "dev"])).to be(true)
      end
    end

    context "when groups includes 'pip'" do
      it "returns true" do
        expect(production_check.call(["pip"])).to be(true)
      end

      it "returns true even with other groups" do
        expect(production_check.call(["dev", "pip", "test"])).to be(true)
      end
    end

    context "when groups includes only non-production groups" do
      it "returns false" do
        expect(production_check.call(["dev", "test", "lint"])).to be(false)
      end

      it "returns false for single non-production group" do
        expect(production_check.call(["dev"])).to be(false)
      end
    end
  end

  describe "name normaliser" do
    subject(:name_normaliser) do
      Dependabot::Dependency.name_normaliser_for_package_manager("conda")
    end

    it "normalises package names using Conda::NameNormaliser" do
      expect(Dependabot::Conda::NameNormaliser).to receive(:normalise).with("SomePackage").and_return("somepackage")

      expect(name_normaliser.call("SomePackage")).to eq("somepackage")
    end
  end
end
