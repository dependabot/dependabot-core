# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency_file"
require "dependabot/python/file_parser/pyproject_files_parser"

RSpec.describe Dependabot::Python::FileParser::PyprojectFilesParser do
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

  describe "parse poetry files" do
    let(:pyproject_fixture_name) { "basic_poetry_dependencies.toml" }

    subject(:dependencies) { parser.dependency_set.dependencies }

    context "without a lockfile" do
      its(:length) { is_expected.to eq(15) }

      it "doesn't include the Python requirement" do
        expect(dependencies.map(&:name)).to_not include("python")
      end

      context "with a string declaration" do
        subject(:dependency) { dependencies.first }

        it "has the right details" do
          expect(dependency).to be_a(Dependabot::Dependency)
          expect(dependency.name).to eq("geopy")
          expect(dependency.version).to be_nil
          expect(dependency.requirements).to eq(
            [{
              requirement: "^1.13",
              file: "pyproject.toml",
              groups: ["dependencies"],
              source: nil
            }]
          )
        end
      end

      context "with an invalid requirement" do
        let(:pyproject_fixture_name) { "invalid_wildcard.toml" }

        it "raises a helpful error" do
          expect { parser.dependency_set }.
            to raise_error do |error|
              expect(error.class).
                to eq(Dependabot::DependencyFileNotEvaluatable)
              expect(error.message).
                to eq('Illformed requirement ["2.18.^"]')
            end
        end
      end

      context "with a path requirement" do
        let(:pyproject_fixture_name) { "dir_dependency.toml" }
        subject(:dependency_names) { dependencies.map(&:name) }

        it "excludes path dependency" do
          expect(dependency_names).to_not include("toml")
        end

        it "includes non-path dependencies" do
          expect(dependency_names).to include("pytest")
        end
      end

      context "with a git requirement" do
        let(:pyproject_fixture_name) { "git_dependency.toml" }
        subject(:dependency_names) { dependencies.map(&:name) }

        it "excludes git dependency" do
          expect(dependency_names).to_not include("toml")
        end

        it "includes non-git dependencies" do
          expect(dependency_names).to include("pytest")
        end
      end

      context "with a url requirement" do
        let(:pyproject_fixture_name) { "url_dependency.toml" }
        subject(:dependency_names) { dependencies.map(&:name) }

        it "excludes url dependency" do
          expect(dependency_names).to_not include("toml")
        end

        it "includes non-url dependencies" do
          expect(dependency_names).to include("pytest")
        end
      end
    end

    context "with a lockfile" do
      let(:files) { [pyproject, poetry_lock] }
      let(:poetry_lock) do
        Dependabot::DependencyFile.new(
          name: "poetry.lock",
          content: pyproject_lock_body
        )
      end
      let(:pyproject_lock_body) do
        fixture("pyproject_locks", pyproject_lock_fixture_name)
      end
      let(:pyproject_lock_fixture_name) { "poetry.lock" }

      its(:length) { is_expected.to eq(36) }

      it "doesn't include the Python requirement" do
        expect(dependencies.map(&:name)).to_not include("python")
      end

      context "that is called pyproject.lock (legacy name)" do
        let(:files) { [pyproject, pyproject_lock] }
        let(:pyproject_lock) do
          Dependabot::DependencyFile.new(
            name: "pyproject.lock",
            content: pyproject_lock_body
          )
        end

        its(:length) { is_expected.to eq(36) }

        describe "a development sub-dependency" do
          subject(:dep) { dependencies.find { |d| d.name == "atomicwrites" } }

          its(:subdependency_metadata) do
            is_expected.to eq([{ production: false }])
          end
        end

        describe "a production sub-dependency" do
          subject(:dep) { dependencies.find { |d| d.name == "certifi" } }

          its(:subdependency_metadata) do
            is_expected.to eq([{ production: true }])
          end
        end
      end

      context "with a path dependency" do
        let(:pyproject_fixture_name) { "dir_dependency.toml" }
        let(:pyproject_lock_fixture_name) { "dir_dependency.lock" }
        subject(:dependency_names) { dependencies.map(&:name) }

        it "excludes the path dependency" do
          expect(dependency_names).to_not include("toml")
        end

        it "includes non-path dependencies" do
          expect(dependency_names).to include("pytest")
        end
      end

      context "with a git dependency" do
        let(:pyproject_fixture_name) { "git_dependency.toml" }
        let(:pyproject_lock_fixture_name) { "git_dependency.lock" }

        it "excludes the git dependency" do
          expect(dependencies.map(&:name)).to_not include("toml")
        end
      end

      context "with a url dependency" do
        let(:pyproject_fixture_name) { "url_dependency.toml" }
        let(:pyproject_lock_fixture_name) { "url_dependency.lock" }

        it "excludes the url dependency" do
          expect(dependencies.map(&:name)).to_not include("toml")
        end
      end

      context "with a manifest declaration" do
        subject(:dependency) { dependencies.find { |f| f.name == "geopy" } }

        it "has the right details" do
          expect(dependency).to be_a(Dependabot::Dependency)
          expect(dependency.name).to eq("geopy")
          expect(dependency.version).to eq("1.14.0")
          expect(dependency.requirements).to eq(
            [{
              requirement: "^1.13",
              file: "pyproject.toml",
              groups: ["dependencies"],
              source: nil
            }]
          )
        end

        context "that has a name that needs normalising" do
          subject(:dependency) { dependencies.find { |f| f.name == "pillow" } }

          it "has the right details" do
            expect(dependency).to be_a(Dependabot::Dependency)
            expect(dependency.name).to eq("pillow")
            expect(dependency.version).to eq("5.1.0")
            expect(dependency.requirements).to eq(
              [{
                requirement: "^5.1",
                file: "pyproject.toml",
                groups: ["dependencies"],
                source: nil
              }]
            )
          end
        end
      end

      context "without a manifest declaration" do
        subject(:dependency) { dependencies.find { |f| f.name == "appdirs" } }

        it "has the right details" do
          expect(dependency).to be_a(Dependabot::Dependency)
          expect(dependency.name).to eq("appdirs")
          expect(dependency.version).to eq("1.4.3")
          expect(dependency.requirements).to eq([])
        end
      end
    end
  end

  describe "parse standard python files" do
    let(:pyproject_fixture_name) { "standard_python.toml" }

    subject(:dependencies) { parser.dependency_set.dependencies }

    its(:length) { is_expected.to eq(1) }

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
            groups: [nil],
            source: nil
          }]
        )
      end
    end

    context "without dependencies" do
      let(:pyproject_fixture_name) { "no_dependencies.toml" }

      subject(:dependencies) { parser.dependency_set.dependencies }

      its(:length) { is_expected.to eq(0) }
    end

    context "with dependencies with empty requirements" do
      let(:pyproject_fixture_name) { "no_requirements.toml" }

      subject(:dependencies) { parser.dependency_set.dependencies }

      its(:length) { is_expected.to eq(0) }
    end

    context "with a PDM project" do
      let(:pyproject_fixture_name) { "pdm_example.toml" }
      let(:pdm_lock) do
        Dependabot::DependencyFile.new(
          name: "pdm.lock",
          content: pdm_lock_body
        )
      end
      let(:pdm_lock_body) do
        fixture("pyproject_locks", pyproject_lock_fixture_name)
      end
      let(:pyproject_lock_fixture_name) { "pdm_example.lock" }
      let(:files) { [pyproject, pdm_lock] }

      subject(:dependencies) { parser.dependency_set.dependencies }

      its(:length) { is_expected.to eq(0) }
    end

    context "with optional dependencies" do
      let(:pyproject_fixture_name) { "optional_dependencies.toml" }

      subject(:dependencies) { parser.dependency_set.dependencies }

      # fixture has 1 runtime dependency, plus 4 optional dependencies, but one
      # is ignored because it has markers
      its(:length) { is_expected.to eq(4) }
    end

    context "with optional dependencies only" do
      let(:pyproject_fixture_name) { "optional_dependencies_only.toml" }

      subject(:dependencies) { parser.dependency_set.dependencies }

      its(:length) { is_expected.to be > 0 }
    end
  end
end
