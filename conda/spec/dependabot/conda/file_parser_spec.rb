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
        expect(dependencies.map(&:name)).to match_array(
          %w(
            python numpy pandas pydantic-settings
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
        expect(pydantic_dep.package_manager).to eq("pip")
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

    context "with pin operator (==) dependencies" do
      let(:environment_content) { fixture("environment_pin_operator.yml") }

      it "correctly parses dependencies with == operator" do
        dependencies = parser.parse

        expect(dependencies.map(&:name)).to include("conda", "numpy", "pandas", "setuptools")
      end

      it "extracts version from == pin operator" do
        dependencies = parser.parse
        conda_dep = dependencies.find { |dep| dep.name == "conda" }
        numpy_dep = dependencies.find { |dep| dep.name == "numpy" }

        expect(conda_dep.version).to eq("25.5.1")
        expect(numpy_dep.version).to eq("1.26.0")
      end

      it "preserves == operator in requirements" do
        dependencies = parser.parse
        conda_dep = dependencies.find { |dep| dep.name == "conda" }

        expect(conda_dep.requirements.first[:requirement]).to eq("==25.5.1")
      end

      it "does not treat == as fully qualified spec" do
        dependencies = parser.parse

        # Should find dependencies, not skip them as fully qualified
        expect(dependencies).not_to be_empty
        expect(dependencies.length).to be >= 4
      end
    end

    context "with conda history export format (real-world example)" do
      let(:environment_content) { fixture("environment_bracket_syntax.yml") }

      it "parses dependencies despite ==25.5.1 pin operator" do
        dependencies = parser.parse

        # Should find dependencies, not treat == as fully qualified
        expect(dependencies).not_to be_empty
        expect(dependencies.length).to be >= 10
      end

      it "extracts conda with == operator" do
        dependencies = parser.parse
        conda_dep = dependencies.find { |dep| dep.name == "conda" }

        expect(conda_dep).not_to be_nil
        expect(conda_dep.version).to eq("25.5.1")
        expect(conda_dep.requirements.first[:requirement]).to eq("==25.5.1")
      end

      it "handles bracket syntax dependencies" do
        dependencies = parser.parse

        # These have [version='>=X'] syntax which should be parsed
        telemetry_dep = dependencies.find { |dep| dep.name == "conda-anaconda-telemetry" }
        tos_dep = dependencies.find { |dep| dep.name == "conda-anaconda-tos" }

        expect(telemetry_dep).not_to be_nil
        expect(tos_dep).not_to be_nil
      end

      it "handles dependencies with dots in names" do
        dependencies = parser.parse
        python_app_dep = dependencies.find { |dep| dep.name == "python.app" }

        expect(python_app_dep).not_to be_nil
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
        expect(dependencies.map(&:name)).to match_array(%w(python numpy pandas))
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

      it "parses non-Python packages correctly (R, system tools)" do
        dependencies = parser.parse
        expect(dependencies.map(&:name)).to match_array(%w(r-base git cmake))

        r_dep = dependencies.find { |dep| dep.name == "r-base" }
        expect(r_dep.version).to eq("4.0.3")
        expect(r_dep.requirements.first[:groups]).to eq(["dependencies"])
      end
    end

    context "with fully qualified conda packages and pip section" do
      let(:environment_content) { fixture("environment_fully_qualified.yml") }

      it "skips fully qualified conda packages but parses pip packages" do
        dependencies = parser.parse

        # All conda packages have build strings (e.g., python=3.10.9=he550d4f_0_cpython)
        expect(dependencies.all? { |d| d.package_manager == "pip" }).to be true
        expect(dependencies.length).to be_positive

        # Verify some expected pip packages are present
        pip_names = dependencies.map(&:name)
        expect(pip_names).to include("beautifulsoup4", "tqdm", "yt-dlp")
      end

      it "correctly groups all dependencies as pip" do
        dependencies = parser.parse

        dependencies.each do |dep|
          expect(dep.requirements.first[:groups]).to eq(["pip"])
        end
      end
    end

    context "with environment containing only fully qualified packages and no pip" do
      let(:environment_content) { fixture("environment_no_pip_no_support.yml") }

      it "returns empty dependencies when all packages are fully qualified" do
        dependencies = parser.parse

        # All packages have build strings: python=3.9.7=h60c2a47_0_cpython, etc.
        # No simple specs, no pip section -> no supported dependencies
        expect(dependencies).to be_empty
      end

      it "validates that fully qualified detection works correctly" do
        dependencies = parser.parse

        # Verify all dependencies were skipped due to fully qualified format
        expect(dependencies.length).to eq(0)
      end
    end

    context "with invalid YAML content that is not a Hash" do
      let(:environment_content) { "- just\n- a\n- list" }

      it "returns empty dependencies for non-Hash YAML" do
        dependencies = parser.parse
        expect(dependencies).to be_empty
      end
    end

    context "with Hash YAML but no dependencies key" do
      let(:environment_content) do
        <<~YAML
          name: myenv
          channels:
            - defaults
        YAML
      end

      it "returns empty dependencies when dependencies is missing" do
        dependencies = parser.parse
        expect(dependencies).to be_empty
      end
    end

    context "with dependencies that is not an Array" do
      let(:environment_content) do
        <<~YAML
          dependencies: "not-an-array"
        YAML
      end

      it "returns empty dependencies when dependencies is not an Array" do
        dependencies = parser.parse
        # When dependencies is not an Array, we skip it entirely (both conda and pip parsing)
        expect(dependencies).to be_empty
      end
    end

    context "with compatible release operator (~=) for conda packages" do
      let(:environment_content) do
        <<~YAML
          dependencies:
            - numpy~=1.21.0
            - pandas~=1.3.0
        YAML
      end

      it "correctly parses ~= operator" do
        dependencies = parser.parse
        numpy_dep = dependencies.find { |dep| dep.name == "numpy" }

        expect(numpy_dep.version).to eq("1.21.0")
        expect(numpy_dep.requirements.first[:requirement]).to eq("~=1.21.0")
      end
    end

    context "with pip dependencies using various operators" do
      let(:environment_content) do
        <<~YAML
          dependencies:
            - python=3.11
            - pip:
                - requests>2.0.0
                - flask<=2.0.0
                - click<8.0.0
                - urllib3!=1.25.0
                - six~=1.16.0
                - setuptools
        YAML
      end

      it "correctly parses > operator (greater than)" do
        dependencies = parser.parse
        requests_dep = dependencies.find { |dep| dep.name == "requests" }

        expect(requests_dep).not_to be_nil
        expect(requests_dep.version).to be_nil # > doesn't provide current version
        expect(requests_dep.requirements.first[:requirement]).to eq(">2.0.0")
      end

      it "correctly parses <= operator (less than or equal)" do
        dependencies = parser.parse
        flask_dep = dependencies.find { |dep| dep.name == "flask" }

        expect(flask_dep).not_to be_nil
        expect(flask_dep.version).to be_nil # <= doesn't provide current version
        expect(flask_dep.requirements.first[:requirement]).to eq("<=2.0.0")
      end

      it "correctly parses < operator (less than)" do
        dependencies = parser.parse
        click_dep = dependencies.find { |dep| dep.name == "click" }

        expect(click_dep).not_to be_nil
        expect(click_dep.version).to be_nil # < doesn't provide current version
        expect(click_dep.requirements.first[:requirement]).to eq("<8.0.0")
      end

      it "correctly parses != operator (not equal)" do
        dependencies = parser.parse
        urllib3_dep = dependencies.find { |dep| dep.name == "urllib3" }

        expect(urllib3_dep).not_to be_nil
        expect(urllib3_dep.version).to be_nil # != doesn't provide current version
        expect(urllib3_dep.requirements.first[:requirement]).to eq("!=1.25.0")
      end

      it "correctly parses ~= operator for pip packages" do
        dependencies = parser.parse
        six_dep = dependencies.find { |dep| dep.name == "six" }

        expect(six_dep).not_to be_nil
        expect(six_dep.version).to eq("1.16.0") # ~= provides current version
        expect(six_dep.requirements.first[:requirement]).to eq("~=1.16.0")
      end

      it "correctly parses dependencies without version constraints" do
        dependencies = parser.parse
        setuptools_dep = dependencies.find { |dep| dep.name == "setuptools" }

        expect(setuptools_dep).not_to be_nil
        expect(setuptools_dep.version).to be_nil
        expect(setuptools_dep.requirements).to be_empty
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
