# typed: false
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
      expect(dependency.requirements)
        .to eq([{ file: "a.rb", requirement: ">= 0", groups: [], source: nil }])
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

      specify { expect { dependency }.not_to raise_error }
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

      specify { expect(dependency1).not_to eq(dependency2) }
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

    context "when dealing with a requirement that isn't top-level" do
      let(:dependency_args) do
        { name: "dep", requirements: [], package_manager: package_manager }
      end

      it { is_expected.to be(true) }

      context "with subdependency metadata" do
        let(:dependency_args) do
          {
            name: "dep",
            requirements: [],
            package_manager: package_manager,
            subdependency_metadata: [{ production: false }]
          }
        end

        it { is_expected.to be(false) }
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
        expect(to_h).to eq(expected)
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
        expect(to_h).to eq(expected)
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
        expect(to_h).to eq(expected)
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
        expect(to_h).to eq(expected)
      end
    end

    context "when a directory is specified" do
      let(:dependency_args) do
        {
          name: "dep",
          requirements: [],
          package_manager: "dummy",
          directory: "/home"
        }
      end

      it do
        expected = {
          "name" => "dep",
          "package_manager" => "dummy",
          "requirements" => [],
          "directory" => "/home"
        }
        expect(to_h).to eq(expected)
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

      it { is_expected.to be_nil }
    end
  end

  describe "#metadata" do
    it "stores metadata given to initialize" do
      dependency = described_class.new(
        name: "dep",
        requirements: [],
        package_manager: "dummy",
        metadata: { foo: 42 }
      )
      expect(dependency.metadata).to eq(foo: 42)
    end

    it "is mutable" do
      dependency = described_class.new(
        name: "dep",
        requirements: [],
        package_manager: "dummy",
        metadata: { foo: 42 }
      )

      dependency.metadata[:all_versions] = []
      expect(dependency.metadata).to eq(foo: 42, all_versions: [])
    end

    it "is not serialized" do
      dependency = described_class.new(
        name: "dep",
        requirements: [],
        package_manager: "dummy",
        metadata: { foo: 42 }
      )
      expect(dependency.to_h.keys).not_to include("metadata")
    end

    it "isn't utilized by the equality operator" do
      dependency1 = described_class.new(
        name: "dep",
        requirements: [],
        package_manager: "dummy",
        metadata: { foo: 42 }
      )
      dependency2 = described_class.new(
        name: "dep",
        requirements: [],
        package_manager: "dummy",
        metadata: { foo: 43 }
      )
      expect(dependency1).to eq(dependency2)
    end
  end

  describe "#all_versions" do
    it "returns an empty array by default" do
      dependency = described_class.new(
        name: "dep",
        requirements: [],
        package_manager: "dummy"
      )

      expect(dependency.all_versions).to eq([])
    end

    it "returns the dependency version if all_version metadata isn't present" do
      dependency = described_class.new(
        name: "dep",
        requirements: [],
        package_manager: "dummy",
        version: "1.0.0"
      )

      expect(dependency.all_versions).to eq(["1.0.0"])
    end

    it "returns all_version metadata if present" do
      dependency = described_class.new(
        name: "dep",
        requirements: [],
        package_manager: "dummy",
        version: "1.0.0",
        metadata: {
          all_versions: [
            described_class.new(
              name: "dep",
              requirements: [],
              package_manager: "dummy",
              version: "1.0.0"
            ),
            described_class.new(
              name: "dep",
              requirements: [],
              package_manager: "dummy",
              version: "2.0.0"
            )
          ]
        }
      )

      expect(dependency.all_versions).to eq(["1.0.0", "2.0.0"])
    end
  end
end
