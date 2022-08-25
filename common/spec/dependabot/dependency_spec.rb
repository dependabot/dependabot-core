# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency"

RSpec.describe Dependabot::Dependency do
  describe ".new" do
    subject(:dependency) { described_class.new(**args) }

    let(:args) do
      {
        name: "dep",
        requirements: requirements,
        package_manager: "dummy"
      }
    end
    let(:requirements) do
      [{
        "file" => "a.rb",
        "requirement" => ">= 0",
        "groups" => [],
        source: nil
      }]
    end

    it "converts string keys to symbols" do
      expect(dependency.requirements).
        to eq([{ file: "a.rb", requirement: ">= 0", groups: [], source: nil }])
    end

    context "with an invalid requirement key" do
      let(:requirements) do
        [{
          "file" => "a.rb",
          "requirement" => ">= 0",
          "groups" => [],
          source: nil,
          unknown: "key"
        }]
      end

      specify { expect { dependency }.to raise_error(/required keys/) }
    end

    context "with a missing requirement key" do
      let(:requirements) do
        [{
          "file" => "a.rb",
          "requirement" => ">= 0",
          source: nil
        }]
      end

      specify { expect { dependency }.to raise_error(/required keys/) }
    end

    context "with a missing requirement key" do
      let(:requirements) do
        [{
          file: "a.rb",
          requirement: ">= 0",
          groups: [],
          source: nil,
          metadata: {}
        }]
      end

      specify { expect { dependency }.to_not raise_error }
    end
  end

  describe ".name_normaliser_for_package_manager" do
    subject(:name_normaliser) do
      described_class.name_normaliser_for_package_manager("dep")
    end

    it "is an identity operator by default" do
      expect(name_normaliser.call("name")).to eq("name")
    end
  end

  describe "#==" do
    let(:args) do
      {
        name: "dep",
        requirements:
          [{ file: "a.rb", requirement: "1", groups: [], source: nil }],
        package_manager: "dummy"
      }
    end

    context "when two dependencies are equal" do
      let(:dependency1) { described_class.new(**args) }
      let(:dependency2) { described_class.new(**args) }

      specify { expect(dependency1).to eq(dependency2) }
    end

    context "when two dependencies are not equal" do
      let(:dependency1) { described_class.new(**args) }
      let(:dependency2) { described_class.new(**args.merge(name: "dep2")) }

      specify { expect(dependency1).to_not eq(dependency2) }
    end
  end

  describe "#production?" do
    subject(:production?) { described_class.new(**dependency_args).production? }

    let(:dependency_args) do
      {
        name: "dep",
        requirements:
          [{ file: "a.rb", requirement: "1", groups: groups, source: nil }],
        package_manager: package_manager
      }
    end
    let(:groups) { [] }
    let(:package_manager) { "dummy" }

    context "for a requirement that isn't top-level" do
      let(:dependency_args) do
        { name: "dep", requirements: [], package_manager: package_manager }
      end

      it { is_expected.to eq(true) }

      context "with subdependency metadata" do
        let(:dependency_args) do
          {
            name: "dep",
            requirements: [],
            package_manager: package_manager,
            subdependency_metadata: [{ production: false }]
          }
        end

        it { is_expected.to eq(false) }
      end
    end
  end

  describe "#display_name" do
    subject(:display_name) { described_class.new(**dependency_args).display_name }

    let(:dependency_args) do
      {
        name: "dep",
        requirements: [],
        package_manager: "dummy"
      }
    end

    it { is_expected.to eq("dep") }
  end

  describe "#to_h" do
    subject(:to_h) { described_class.new(**dependency_args).to_h }

    context "with requirements" do
      let(:dependency_args) do
        {
          name: "dep",
          requirements:
            [{ file: "a.rb", requirement: "1", groups: [], source: nil }],
          package_manager: "dummy"
        }
      end

      it do
        expected = {
          "name" => "dep",
          "package_manager" => "dummy",
          "requirements" => [{ file: "a.rb", groups: [],
                               requirement: "1", source: nil }]
        }
        is_expected.to eq(expected)
      end
    end

    context "without requirements" do
      let(:dependency_args) do
        {
          name: "dep",
          requirements: [],
          package_manager: "dummy"
        }
      end

      it do
        expected = {
          "name" => "dep",
          "package_manager" => "dummy",
          "requirements" => []
        }
        is_expected.to eq(expected)
      end
    end

    context "with subdependency metadata" do
      let(:dependency_args) do
        {
          name: "dep",
          requirements: [],
          package_manager: "dummy",
          subdependency_metadata: [{ npm_bundled: true }]
        }
      end

      it do
        expected = {
          "name" => "dep",
          "package_manager" => "dummy",
          "requirements" => [],
          "subdependency_metadata" => [{ npm_bundled: true }]
        }
        is_expected.to eq(expected)
      end
    end

    context "when removed" do
      let(:dependency_args) do
        {
          name: "dep",
          requirements: [],
          package_manager: "dummy",
          removed: true
        }
      end

      it do
        expected = {
          "name" => "dep",
          "package_manager" => "dummy",
          "requirements" => [],
          "removed" => true
        }
        is_expected.to eq(expected)
      end
    end
  end

  describe "#subdependency_metadata" do
    subject(:subdependency_metadata) do
      described_class.new(**dependency_args).subdependency_metadata
    end

    let(:dependency_args) do
      {
        name: "dep",
        requirements: [],
        package_manager: "dummy",
        subdependency_metadata: [{ npm_bundled: true }]
      }
    end

    it { is_expected.to eq([{ npm_bundled: true }]) }

    context "when top level" do
      let(:dependency_args) do
        {
          name: "dep",
          requirements:
            [{ file: "a.rb", requirement: "1", groups: [], source: nil }],
          package_manager: "dummy",
          subdependency_metadata: [{ npm_bundled: true }]
        }
      end

      it { is_expected.to eq(nil) }
    end
  end
end
