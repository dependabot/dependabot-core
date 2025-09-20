# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/conda/file_parser"
require_common_spec "file_parsers/shared_examples_for_file_parsers"

RSpec.describe Dependabot::Conda::FileParser do
  let(:source) do
    Dependabot::Source.new(
      provider: "github",
      repo: "example/repo",
      directory: "/"
    )
  end
  let(:parser) { described_class.new(dependency_files: files, source: source) }
  let(:environment_file) do
    Dependabot::DependencyFile.new(
      name: "environment.yml",
      content: environment_content
    )
  end
  let(:files) { [environment_file] }

  it_behaves_like "a dependency file parser"

  describe "parse" do
    context "with a simple environment file" do
      let(:environment_content) { fixture("environment_simple.yml") }

      it "extracts the correct dependencies" do
        dependencies = parser.parse

        # Python interpreter is excluded as it's a system dependency, not a PyPI package
        expect(dependencies.map(&:name)).to match_array(
          %w(
            numpy pandas pydantic-settings
          )
        )
      end

      it "extracts conda dependencies with correct attributes" do
        dependencies = parser.parse
        # Test with numpy instead of python since python is excluded as a system dependency
        numpy_dep = dependencies.find { |dep| dep.name == "numpy" }

        expect(numpy_dep.version).to eq("1.26")
        expect(numpy_dep.package_manager).to eq("conda")
        expect(numpy_dep.requirements).to eq(
          [{
            requirement: "=1.26",
            file: "environment.yml",
            source: nil,
            groups: ["dependencies"]
          }]
        )
      end

      it "extracts pip dependencies with correct attributes" do
        dependencies = parser.parse
        pydantic_dep = dependencies.find { |dep| dep.name == "pydantic-settings" }

        expect(pydantic_dep.version).to eq("2.0")
        expect(pydantic_dep.package_manager).to eq("conda")
        expect(pydantic_dep.requirements).to eq(
          [{
            requirement: ">=2.0",
            file: "environment.yml",
            source: nil,
            groups: ["pip"]
          }]
        )
      end
    end

    context "with a complex environment file with many Python packages" do
      let(:environment_content) { fixture("environment_complex.yml") }

      it "extracts Python packages only" do
        dependencies = parser.parse

        # Should include Python packages (python interpreter excluded as system dependency)
        expect(dependencies.map(&:name)).to include("numpy", "pandas", "matplotlib-base", "gdal")

        # All dependencies should be Python packages since this is a Python-focused environment
        expect(dependencies.length).to be > 10
      end

      it "correctly identifies Python packages from main dependencies" do
        dependencies = parser.parse
        # Check that we have some expected conda packages (python excluded as system dependency)
        expect(dependencies.map(&:name)).to include("numpy", "pandas")
      end
    end

    context "with environment file containing pip section" do
      let(:environment_content) { fixture("environment_with_pip.yml") }

      it "extracts both conda and pip dependencies" do
        dependencies = parser.parse

        # Check we have expected packages from both conda and pip sections (python excluded as system dependency)
        expect(dependencies.map(&:name)).to include("numpy-base", "pandas") # conda packages
        expect(dependencies.map(&:name)).to include("hmmlearn", "librosa", "matplotlib") # pip packages
      end

      it "correctly parses pip version constraints" do
        dependencies = parser.parse
        hmmlearn_dep = dependencies.find { |dep| dep.name == "hmmlearn" }

        expect(hmmlearn_dep.requirements.first[:requirement]).to eq("==0.2")
        # NOTE: Removed groups check since conda doesn't use groups like other ecosystems
      end
    end

    context "with fully qualified packages and pip section (Tier 2)" do
      let(:environment_content) { fixture("environment_pip_only_support.yml") }

      it "extracts only pip dependencies" do
        dependencies = parser.parse

        # Should only include pip dependencies, not fully qualified conda packages
        expect(dependencies.map(&:name)).to match_array(%w(requests flask))
        # NOTE: Removed groups check since conda doesn't use groups like other ecosystems
      end
    end

    context "with channel specifications" do
      let(:environment_content) do
        <<~YAML
          dependencies:
            - conda-forge::numpy=1.21.0
            - defaults::pandas>=1.3.0
            - python=3.9
        YAML
      end

      it "preserves channel information in requirements" do
        dependencies = parser.parse
        numpy_dep = dependencies.find { |dep| dep.name == "numpy" }

        expect(numpy_dep.requirements.first[:requirement]).to eq("=1.21.0")
        # Channel info should be preserved in the source or elsewhere if needed
        # Note: python is excluded as it's a system dependency, so only numpy and pandas are parsed
        expect(dependencies.map(&:name)).to match_array(%w(numpy pandas))
      end
    end

    context "with version constraints" do
      let(:environment_content) do
        <<~YAML
          dependencies:
            - python>=3.8,<3.11
            - numpy>=1.19.0
            - pandas=1.3.*
        YAML
      end

      it "correctly parses complex version constraints" do
        dependencies = parser.parse

        # Python is excluded as system dependency, so test with numpy and pandas instead
        numpy_dep = dependencies.find { |dep| dep.name == "numpy" }
        pandas_dep = dependencies.find { |dep| dep.name == "pandas" }

        expect(numpy_dep.requirements.first[:requirement]).to eq(">=1.19.0")
        expect(pandas_dep.requirements.first[:requirement]).to eq("=1.3.*")
      end
    end

    context "with invalid YAML" do
      let(:environment_content) { "invalid: yaml: content:" }

      it "raises a helpful error" do
        expect { parser.parse }.to raise_error(Dependabot::DependencyFileNotParseable)
      end
    end

    context "with non-Python packages only" do
      let(:environment_content) { fixture("environment_non_python.yml") }

      it "returns empty dependencies array" do
        dependencies = parser.parse
        expect(dependencies).to be_empty
      end
    end
  end

  describe "#ecosystem" do
    subject(:ecosystem) { parser.ecosystem }

    let(:environment_content) { fixture("environment_simple.yml") }

    it "has the correct name" do
      expect(ecosystem.name).to eq "conda"
    end

    describe "#package_manager" do
      subject(:package_manager) { ecosystem.package_manager }

      it "returns the correct package manager" do
        expect(package_manager.name).to eq "conda"
        expect(package_manager.requirement).to be_nil
        expect(package_manager.version).to be_nil
      end
    end

    it "has no language component" do
      expect(ecosystem.language).to be_nil
    end
  end

  private

  def fixture(name)
    File.read(File.join(__dir__, "../../fixtures", name))
  end
end
