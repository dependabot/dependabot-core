# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/conda/file_updater"
require_common_spec "file_updaters/shared_examples_for_file_updaters"

RSpec.describe Dependabot::Conda::FileUpdater do
  it_behaves_like "a dependency file updater"

  let(:updater) do
    described_class.new(
      dependency_files: dependency_files,
      dependencies: dependencies,
      credentials: github_credentials
    )
  end

  let(:dependency_files) { [environment_file] }
  let(:environment_file) do
    Dependabot::DependencyFile.new(
      name: "environment.yml",
      content: environment_content
    )
  end

  let(:github_credentials) do
    [{
      "type" => "git_source",
      "host" => "github.com",
      "username" => "x-access-token",
      "password" => "token"
    }]
  end

  describe "#updated_dependency_files" do
    context "updating a conda dependency" do
      let(:environment_content) { fixture("environment_simple.yml") }
      let(:dependencies) do
        [Dependabot::Dependency.new(
          name: "numpy",
          version: "1.27.0",
          previous_version: "1.26",
          package_manager: "conda",
          requirements: [{
            requirement: "=1.27.0",
            file: "environment.yml",
            source: nil,
            groups: ["dependencies"]
          }],
          previous_requirements: [{
            requirement: "=1.26",
            file: "environment.yml",
            source: nil,
            groups: ["dependencies"]
          }]
        )]
      end

      it "updates the version in the environment file" do
        updated_files = updater.updated_dependency_files

        expect(updated_files.first.content).to include("numpy=1.27.0")
        expect(updated_files.first.content).not_to include("numpy=1.26")
      end

      it "preserves YAML structure and comments" do
        updated_files = updater.updated_dependency_files

        expect(updated_files.first.content).to include("python=3.11")
        expect(updated_files.first.content).to include("pip  # so pip is present if needed")
        expect(updated_files.first.content).to include("pip:")
      end
    end

    context "updating a pip dependency" do
      let(:environment_content) { fixture("environment_simple.yml") }
      let(:dependencies) do
        [Dependabot::Dependency.new(
          name: "pydantic-settings",
          version: "2.1.0",
          previous_version: nil,
          package_manager: "conda",
          requirements: [{
            requirement: ">=2.1.0",
            file: "environment.yml",
            source: nil,
            groups: ["pip"]
          }],
          previous_requirements: [{
            requirement: ">=2.0",
            file: "environment.yml",
            source: nil,
            groups: ["pip"]
          }]
        )]
      end

      it "updates the pip section dependency" do
        updated_files = updater.updated_dependency_files

        expect(updated_files.first.content).to include("pydantic-settings>=2.1.0")
        expect(updated_files.first.content).not_to include("pydantic-settings>=2.0")
      end

      it "preserves YAML structure and comments" do
        updated_files = updater.updated_dependency_files

        expect(updated_files.first.content).to include("python=3.11")
        expect(updated_files.first.content).to include("pip  # so pip is present if needed")
      end
    end

    context "updating dependency with channel specification" do
      let(:environment_content) do
        <<~YAML
          dependencies:
            - conda-forge::numpy=1.21.0
            - python=3.9
            - pip:
              - requests==2.25.1
        YAML
      end
      let(:dependencies) do
        [Dependabot::Dependency.new(
          name: "numpy",
          version: "1.22.0",
          previous_version: "1.21.0",
          package_manager: "conda",
          requirements: [{
            requirement: "=1.22.0",
            file: "environment.yml",
            source: nil,
            groups: ["dependencies"]
          }],
          previous_requirements: [{
            requirement: "=1.21.0",
            file: "environment.yml",
            source: nil,
            groups: ["dependencies"]
          }]
        )]
      end

      it "preserves channel specification when updating" do
        updated_files = updater.updated_dependency_files

        expect(updated_files.first.content).to include("conda-forge::numpy=1.22.0")
        expect(updated_files.first.content).not_to include("conda-forge::numpy=1.21.0")
      end
    end

    context "updating multiple dependencies" do
      let(:environment_content) { fixture("environment_with_pip.yml") }
      let(:dependencies) do
        [
          Dependabot::Dependency.new(
            name: "python",
            version: "3.9",
            previous_version: "3.8",
            package_manager: "conda",
            requirements: [{
              requirement: "=3.9",
              file: "environment.yml",
              source: nil,
              groups: ["dependencies"]
            }],
            previous_requirements: [{
              requirement: "=3.8",
              file: "environment.yml",
              source: nil,
              groups: ["dependencies"]
            }]
          ),
          Dependabot::Dependency.new(
            name: "requests",
            version: "2.26.0",
            previous_version: nil,
            package_manager: "conda",
            requirements: [{
              requirement: "==2.26.0",
              file: "environment.yml",
              source: nil,
              groups: ["pip"]
            }],
            previous_requirements: [{
              requirement: ">=2.25.0",
              file: "environment.yml",
              source: nil,
              groups: ["pip"]
            }]
          )
        ]
      end

      it "updates multiple dependencies correctly" do
        updated_files = updater.updated_dependency_files

        expect(updated_files.first.content).to include("python=3.9")
        expect(updated_files.first.content).not_to include("python=3.8")

        # Note: The pip dependencies in the fixture don't include requests,
        # but this tests the logic for multiple updates
      end
    end

    context "with complex version constraints" do
      let(:environment_content) do
        <<~YAML
          dependencies:
            - python>=3.8,<3.11
            - numpy>=1.19.0,<1.22
            - pip:
              - pandas>=1.3.0,<1.5.0
        YAML
      end
      let(:dependencies) do
        [Dependabot::Dependency.new(
          name: "numpy",
          version: "1.21.5",
          previous_version: "1.20.0",
          package_manager: "conda",
          requirements: [{
            requirement: ">=1.21.0,<1.22",
            file: "environment.yml",
            source: nil,
            groups: ["dependencies"]
          }],
          previous_requirements: [{
            requirement: ">=1.19.0,<1.22",
            file: "environment.yml",
            source: nil,
            groups: ["dependencies"]
          }]
        )]
      end

      it "updates complex version constraints" do
        updated_files = updater.updated_dependency_files

        expect(updated_files.first.content).to include("numpy>=1.21.0,<1.22")
        expect(updated_files.first.content).not_to include("numpy>=1.19.0,<1.22")
      end
    end

    context "when no dependencies need updating" do
      let(:environment_content) { fixture("environment_simple.yml") }
      let(:dependencies) { [] }

      it "returns the original file unchanged" do
        updated_files = updater.updated_dependency_files

        expect(updated_files.first.content).to eq(environment_content)
      end
    end

    context "with dependency not found in file" do
      let(:environment_content) { fixture("environment_simple.yml") }
      let(:dependencies) do
        [Dependabot::Dependency.new(
          name: "nonexistent-package",
          version: "1.0.0",
          previous_version: "0.9.0",
          package_manager: "conda",
          requirements: [{
            requirement: "=1.0.0",
            file: "environment.yml",
            source: nil,
            groups: ["dependencies"]
          }],
          previous_requirements: [{
            requirement: "=0.9.0",
            file: "environment.yml",
            source: nil,
            groups: ["dependencies"]
          }]
        )]
      end

      it "raises an appropriate error" do
        expect { updater.updated_dependency_files }.to raise_error(
          /Unable to find dependency nonexistent-package/
        )
      end
    end

    context "with multiple dependencies where one is not found" do
      let(:environment_content) { fixture("environment_simple.yml") }
      let(:dependencies) do
        [
          Dependabot::Dependency.new(
            name: "numpy",
            version: "1.27.0",
            previous_version: "1.26",
            package_manager: "conda",
            requirements: [{
              requirement: "=1.27.0",
              file: "environment.yml",
              source: nil,
              groups: ["dependencies"]
            }],
            previous_requirements: [{
              requirement: "=1.26",
              file: "environment.yml",
              source: nil,
              groups: ["dependencies"]
            }]
          ),
          Dependabot::Dependency.new(
            name: "nonexistent-package",
            version: "1.0.0",
            previous_version: "0.9.0",
            package_manager: "conda",
            requirements: [{
              requirement: "=1.0.0",
              file: "environment.yml",
              source: nil,
              groups: ["dependencies"]
            }],
            previous_requirements: [{
              requirement: "=0.9.0",
              file: "environment.yml",
              source: nil,
              groups: ["dependencies"]
            }]
          )
        ]
      end

      it "updates found dependencies and skips missing ones" do
        updated_files = updater.updated_dependency_files

        expect(updated_files.first.content).to include("numpy=1.27.0")
        expect(updated_files.first.content).not_to include("numpy=1.26")
      end
    end

    context "with dependency that has no version" do
      let(:environment_content) { fixture("environment_simple.yml") }
      let(:dependencies) do
        [Dependabot::Dependency.new(
          name: "numpy",
          version: nil,
          previous_version: "1.26",
          package_manager: "conda",
          requirements: [{
            requirement: nil,
            file: "environment.yml",
            source: nil,
            groups: ["dependencies"]
          }],
          previous_requirements: [{
            requirement: "=1.26",
            file: "environment.yml",
            source: nil,
            groups: ["dependencies"]
          }]
        )]
      end

      it "returns the original file unchanged" do
        updated_files = updater.updated_dependency_files

        expect(updated_files.first.content).to eq(environment_content)
      end
    end

    context "with invalid YAML structure" do
      let(:environment_content) do
        <<~YAML
          dependencies: "not an array"
        YAML
      end
      let(:dependencies) do
        [Dependabot::Dependency.new(
          name: "numpy",
          version: "1.27.0",
          previous_version: "1.26",
          package_manager: "conda",
          requirements: [{
            requirement: "=1.27.0",
            file: "environment.yml",
            source: nil,
            groups: ["dependencies"]
          }],
          previous_requirements: [{
            requirement: "=1.26",
            file: "environment.yml",
            source: nil,
            groups: ["dependencies"]
          }]
        )]
      end

      it "returns the original file when YAML structure is invalid" do
        updated_files = updater.updated_dependency_files

        expect(updated_files.first.content).to eq(environment_content)
      end
    end

    context "with unparseable YAML" do
      let(:environment_content) do
        <<~YAML
          dependencies:
            - python=3.11
          invalid_yaml: [
        YAML
      end
      let(:dependencies) do
        [Dependabot::Dependency.new(
          name: "numpy",
          version: "1.27.0",
          previous_version: "1.26",
          package_manager: "conda",
          requirements: [{
            requirement: "=1.27.0",
            file: "environment.yml",
            source: nil,
            groups: ["dependencies"]
          }],
          previous_requirements: [{
            requirement: "=1.26",
            file: "environment.yml",
            source: nil,
            groups: ["dependencies"]
          }]
        )]
      end

      it "raises a DependencyFileNotParseable error" do
        expect { updater.updated_dependency_files }.to raise_error(
          Dependabot::DependencyFileNotParseable,
          /Invalid YAML in environment.yml/
        )
      end
    end

    context "with dependency that has empty requirements" do
      let(:environment_content) { fixture("environment_simple.yml") }
      let(:dependencies) do
        [Dependabot::Dependency.new(
          name: "numpy",
          version: "1.27.0",
          previous_version: "1.26",
          package_manager: "conda",
          requirements: [],
          previous_requirements: [{
            requirement: "=1.26",
            file: "environment.yml",
            source: nil,
            groups: ["dependencies"]
          }]
        )]
      end

      it "uses default conda requirement format" do
        updated_files = updater.updated_dependency_files

        expect(updated_files.first.content).to include("numpy=1.27.0")
      end
    end

    context "with pip dependency that has empty requirements" do
      let(:environment_content) { fixture("environment_simple.yml") }
      let(:dependencies) do
        [Dependabot::Dependency.new(
          name: "pydantic-settings",
          version: "2.1.0",
          previous_version: "2.0.0",
          package_manager: "conda",
          requirements: [],
          previous_requirements: [{
            requirement: ">=2.0",
            file: "environment.yml",
            source: nil,
            groups: ["pip"]
          }]
        )]
      end

      it "uses default pip requirement format" do
        updated_files = updater.updated_dependency_files

        expect(updated_files.first.content).to include("pydantic-settings==2.1.0")
      end
    end
  end

  describe "#check_required_files" do
    context "when no environment files are present" do
      let(:dependency_files) do
        [Dependabot::DependencyFile.new(name: "requirements.txt", content: "numpy==1.26")]
      end
      let(:dependencies) { [] }

      it "raises an error" do
        expect { updater.updated_dependency_files }.to raise_error(
          "No environment.yml file found!"
        )
      end
    end
  end

  private

  def fixture(name)
    File.read(File.join(__dir__, "../../fixtures", name))
  end
end
