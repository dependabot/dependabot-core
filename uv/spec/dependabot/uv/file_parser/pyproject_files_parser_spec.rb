# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency_file"
require "dependabot/uv"

RSpec.describe Dependabot::Uv::FileParser::PyprojectFilesParser do
  let(:parser) { described_class.new(dependency_files: files) }

  let(:files) { [pyproject] }
  let(:pyproject) do
    Dependabot::DependencyFile.new(
      name: "pyproject.toml",
      content: pyproject_body
    )
  end
  let(:pyproject_body) do
    fixture("pyproject_files", pyproject_fixture_name)
  end

  describe "parse standard python files" do
    subject(:dependencies) { parser.dependency_set.dependencies }

    let(:pyproject_fixture_name) { "standard_python.toml" }

    # fixture has 1 build system requires and plus 1 dependencies exists

    its(:length) { is_expected.to eq(2) }

    context "with a string declaration" do
      subject(:dependency) { dependencies.first }

      it "has the right details" do
        expect(dependency).to be_a(Dependabot::Dependency)
        expect(dependency.name).to eq("ansys-templates")
        expect(dependency.version).to eq("0.3.0")
        expect(dependency.requirements).to eq(
          [{
            requirement: "==0.3.0",
            file: "pyproject.toml",
            groups: [],
            source: nil
          }]
        )
        expect(dependency).to be_production
      end
    end

    context "without dependencies" do
      subject(:dependencies) { parser.dependency_set.dependencies }

      let(:pyproject_fixture_name) { "no_dependencies.toml" }

      # fixture has 1 build system requires and no dependencies or
      # optional dependencies exists

      its(:length) { is_expected.to eq(1) }
    end

    context "with dependencies with empty requirements" do
      subject(:dependencies) { parser.dependency_set.dependencies }

      let(:pyproject_fixture_name) { "no_requirements.toml" }

      # certifi (from project.dependencies)
      # hatchling (from build-system.requires)
      # hatch-fancy-pypi-readme (from build-system.requires)
      its(:length) { is_expected.to eq(3) }
    end

    context "with optional dependencies" do
      subject(:dependencies) { parser.dependency_set.dependencies }

      let(:pyproject_fixture_name) { "optional_dependencies.toml" }

      # fixture has 1 runtime dependency, plus 4 optional dependencies, but one
      # is ignored because it has markers, plus 1 is build system requires
      its(:length) { is_expected.to eq(5) }
    end

    describe "parse standard python files" do
      subject(:dependencies) { parser.dependency_set.dependencies }

      let(:pyproject_fixture_name) { "pyproject_1_0_0.toml" }

      # pydantic (from project.dependencies)
      # setuptools (from build-system.requires)
      # setuptools-scm (from build-system.requires)
      its(:length) { is_expected.to eq(3) }

      context "with a string declaration" do
        subject(:dependency) { dependencies.first }

        it "has the right details" do
          expect(dependency).to be_a(Dependabot::Dependency)
          expect(dependency.name).to eq("pydantic")
          expect(dependency.version).to eq("2.7.0")
        end
      end

      context "without dependencies" do
        subject(:dependencies) { parser.dependency_set.dependencies }

        let(:pyproject_fixture_name) { "pyproject_1_0_0_nodeps.toml" }

        # setuptools (from build-system.requires)
        # setuptools-scm (from build-system.requires)
        its(:length) { is_expected.to eq(2) }
      end
    end

    describe "with pep 735" do
      subject(:dependencies) { parser.dependency_set.dependencies }

      let(:pyproject_fixture_name) { "pep735_exact_requirement.toml" }

      # looks like this:

      ###
      # dependencies = []
      #
      # [dependency-groups]
      # test = [
      #   "pytest==8.0.0",
      # ]
      # dev = ["requests==2.18.0", {include-group = "test"}]

      its(:length) { is_expected.to eq(2) }

      it "has both dependencies" do
        expected_deps = [
          { name: "pytest", version: "8.0.0" },
          { name: "requests", version: "2.18.0" }
        ]

        actual_deps = dependencies.map { |dep| { name: dep.name, version: dep.version } }
        expect(actual_deps).to match_array(expected_deps)
      end
    end

    describe "with uv path dependency" do
      subject(:dependencies) { parser.dependency_set.dependencies }

      let(:pyproject_fixture_name) { "uv_path_dependencies.toml" }

      its(:length) { is_expected.to eq(5) }

      it "has all dependencies" do
        expected_deps = [
          { name: "requests" },
          { name: "protos" },
          { name: "another-local" },
          { name: "setuptools" },
          { name: "wheel" }
        ]

        actual_deps = dependencies.map { |dep| { name: dep.name } }
        expect(actual_deps).to match_array(expected_deps)
      end
    end
  end
end
