# frozen_string_literal: true

require "spec_helper"
require "dependabot/npm_and_yarn/file_parser"
require "dependabot/npm_and_yarn/helpers"

RSpec.describe Dependabot::NpmAndYarn::Helpers do
  describe "::dependencies_with_all_versions_metadata" do
    let(:foo_a) do
      Dependabot::Dependency.new(
        name: "foo",
        version: "0.0.1",
        requirements: [{
          requirement: "^0.0.1",
          file: "package.json",
          groups: nil,
          source: nil
        }],
        package_manager: "npm_and_yarn"
      )
    end

    let(:foo_b) do
      Dependabot::Dependency.new(
        name: "foo",
        version: "0.0.2",
        requirements: [{
          requirement: "^0.0.1",
          file: "package-lock.json",
          groups: ["dependencies"],
          source: { type: "registry", url: "https://registry.npmjs.org" }
        }],
        package_manager: "npm_and_yarn"
      )
    end

    let(:foo_c) do
      Dependabot::Dependency.new(
        name: "foo",
        version: "0.0.3",
        requirements: [{
          requirement: "^0.0.3",
          file: "package-lock.json",
          groups: ["dependencies"],
          source: { type: "registry", url: "https://registry.npmjs.org" }
        }],
        package_manager: "npm_and_yarn"
      )
    end

    let(:bar_a) do
      Dependabot::Dependency.new(
        name: "bar",
        version: "0.2.1",
        requirements: [{
          requirement: "^0.2.1",
          file: "package.json",
          groups: ["dependencies"],
          source: nil
        }],
        package_manager: "npm_and_yarn"
      )
    end

    let(:bar_b) do
      Dependabot::Dependency.new(
        name: "bar",
        version: "0.2.2",
        requirements: [{
          requirement: "^0.2.1",
          file: "package-lock.json",
          groups: ["dependencies"],
          source: { type: "registry", url: "https://registry.npmjs.org" }
        }],
        package_manager: "npm_and_yarn"
      )
    end

    let(:bar_c) do
      Dependabot::Dependency.new(
        name: "bar",
        version: "0.2.3",
        requirements: [{
          requirement: "^0.2.3",
          file: "package-lock.json",
          groups: ["dependencies"],
          source: { type: "registry", url: "https://registry.npmjs.org" }
        }],
        package_manager: "npm_and_yarn"
      )
    end

    it "returns flattened list of dependencies populated with :all_versions metadata" do
      dependency_set = Dependabot::NpmAndYarn::FileParser::DependencySet.new
      dependency_set << foo_a << bar_a << foo_c << bar_c << foo_b << bar_b

      expect(described_class.dependencies_with_all_versions_metadata(dependency_set)).to eq([
        Dependabot::Dependency.new(
          name: "foo",
          version: "0.0.1",
          requirements: (foo_a.requirements + foo_c.requirements + foo_b.requirements).uniq,
          package_manager: "npm_and_yarn",
          metadata: { all_versions: [foo_a, foo_c, foo_b] }
        ),
        Dependabot::Dependency.new(
          name: "bar",
          version: "0.2.1",
          requirements: (bar_a.requirements + bar_c.requirements + bar_b.requirements).uniq,
          package_manager: "npm_and_yarn",
          metadata: { all_versions: [bar_a, bar_c, bar_b] }
        )
      ])
    end

    context "when dependencies in set already have :all_versions metadata" do
      it "correctly merges existing metadata into new metadata" do
        dependency_set = Dependabot::NpmAndYarn::FileParser::DependencySet.new
        dependency_set << foo_a
        dependency_set << Dependabot::Dependency.new(
          name: "foo",
          version: "0.0.3",
          requirements: (foo_c.requirements + foo_b.requirements).uniq,
          package_manager: "npm_and_yarn",
          metadata: { all_versions: [foo_c, foo_b] }
        )
        dependency_set << bar_c
        dependency_set << bar_b
        dependency_set << Dependabot::Dependency.new(
          name: "bar",
          version: "0.2.1",
          requirements: bar_a.requirements,
          package_manager: "npm_and_yarn",
          metadata: { all_versions: [bar_a] }
        )

        expect(described_class.dependencies_with_all_versions_metadata(dependency_set)).to eq([
          Dependabot::Dependency.new(
            name: "foo",
            version: "0.0.1",
            requirements: (foo_a.requirements + foo_c.requirements + foo_b.requirements).uniq,
            package_manager: "npm_and_yarn",
            metadata: { all_versions: [foo_a, foo_c, foo_b] }
          ),
          Dependabot::Dependency.new(
            name: "bar",
            version: "0.2.1",
            requirements: (bar_c.requirements + bar_b.requirements + bar_a.requirements).uniq,
            package_manager: "npm_and_yarn",
            metadata: { all_versions: [bar_c, bar_b, bar_a] }
          )
        ])
      end
    end
  end
end
