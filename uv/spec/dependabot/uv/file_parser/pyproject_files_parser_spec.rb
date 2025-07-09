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

  describe "parse poetry files" do
    subject(:dependencies) { parser.dependency_set.dependencies }

    let(:pyproject_fixture_name) { "basic_poetry_dependencies.toml" }

    context "without a lockfile" do
      its(:length) { is_expected.to eq(15) }

      it "doesn't include the Python requirement" do
        expect(dependencies.map(&:name)).not_to include("python")
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
          expect { parser.dependency_set }
            .to raise_error do |error|
              expect(error.class)
                .to eq(Dependabot::DependencyFileNotEvaluatable)
              expect(error.message)
                .to eq('Illformed requirement ["2.18.^"]')
            end
        end
      end

      context "with a path requirement" do
        subject(:dependency_names) { dependencies.map(&:name) }

        let(:pyproject_fixture_name) { "dir_dependency.toml" }

        it "excludes path dependency" do
          expect(dependency_names).not_to include("toml")
        end

        it "includes non-path dependencies" do
          expect(dependency_names).to include("pytest")
        end
      end

      context "with a git requirement" do
        subject(:dependency_names) { dependencies.map(&:name) }

        let(:pyproject_fixture_name) { "git_dependency.toml" }

        it "excludes git dependency" do
          expect(dependency_names).not_to include("toml")
        end

        it "includes non-git dependencies" do
          expect(dependency_names).to include("pytest")
        end
      end

      context "with a url requirement" do
        subject(:dependency_names) { dependencies.map(&:name) }

        let(:pyproject_fixture_name) { "url_dependency.toml" }

        it "excludes url dependency" do
          expect(dependency_names).not_to include("toml")
        end

        it "includes non-url dependencies" do
          expect(dependency_names).to include("pytest")
        end
      end

      context "with non-package mode" do
        let(:pyproject_fixture_name) { "poetry_non_package_mode.toml" }

        it "parses correctly with no metadata" do
          expect { parser.dependency_set }.not_to raise_error
        end
      end
    end

    context "with a lockfile" do
      let(:files) { [pyproject, poetry_lock] }
      let(:poetry_lock) do
        Dependabot::DependencyFile.new(
          name: "poetry.lock",
          content: poetry_lock_body
        )
      end
      let(:poetry_lock_body) do
        fixture("poetry_locks", poetry_lock_fixture_name)
      end
      let(:poetry_lock_fixture_name) { "poetry.lock" }

      its(:length) { is_expected.to eq(36) }

      it "doesn't include the Python requirement" do
        expect(dependencies.map(&:name)).not_to include("python")
      end

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

      context "with a path dependency" do
        subject(:dependency_names) { dependencies.map(&:name) }

        let(:pyproject_fixture_name) { "dir_dependency.toml" }
        let(:poetry_lock_fixture_name) { "dir_dependency.lock" }

        it "excludes the path dependency" do
          expect(dependency_names).not_to include("toml")
        end

        it "includes non-path dependencies" do
          expect(dependency_names).to include("pytest")
        end
      end

      context "with a git dependency" do
        let(:pyproject_fixture_name) { "git_dependency.toml" }
        let(:poetry_lock_fixture_name) { "git_dependency.lock" }

        it "excludes the git dependency" do
          expect(dependencies.map(&:name)).not_to include("toml")
        end
      end

      context "with a url dependency" do
        let(:pyproject_fixture_name) { "url_dependency.toml" }
        let(:poetry_lock_fixture_name) { "url_dependency.lock" }

        it "excludes the url dependency" do
          expect(dependencies.map(&:name)).not_to include("toml")
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

        context "when having a name that needs normalising" do
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

    context "with group dependencies" do
      subject(:dependency_names) { dependencies.map(&:name) }

      let(:pyproject_fixture_name) { "poetry_group_dependencies.toml" }

      it "includes dev-dependencies and group.dev.dependencies" do
        expect(dependency_names).to include("black")
        expect(dependency_names).to include("pytest")
      end

      it "includes other group dependencies" do
        expect(dependency_names).to include("sphinx")
      end
    end

    context "with package specify source" do
      subject(:dependency) { dependencies.find { |f| f.name == "black" } }

      let(:pyproject_fixture_name) { "package_specify_source.toml" }

      it "specifies a package source" do
        expect(dependency.requirements[0][:source]).to eq("custom")
      end
    end
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

      its(:length) { is_expected.to eq(0) }
    end

    context "with a PDM project" do
      subject(:dependencies) { parser.dependency_set.dependencies }

      let(:pyproject_fixture_name) { "pdm_example.toml" }
      let(:pdm_lock) do
        Dependabot::DependencyFile.new(
          name: "pdm.lock",
          content: pdm_lock_body
        )
      end
      let(:pdm_lock_body) do
        fixture("poetry_locks", poetry_lock_fixture_name)
      end
      let(:poetry_lock_fixture_name) { "pdm_example.lock" }
      let(:files) { [pyproject, pdm_lock] }

      its(:length) { is_expected.to eq(0) }

      context "when a leftover poetry.lock is present" do
        let(:poetry_lock) do
          Dependabot::DependencyFile.new(
            name: "poetry.lock",
            content: poetry_lock_body
          )
        end
        let(:poetry_lock_body) do
          fixture("poetry_locks", poetry_lock_fixture_name)
        end
        let(:poetry_lock_fixture_name) { "poetry.lock" }

        let(:files) { [pyproject, pdm_lock, poetry_lock] }

        its(:length) { is_expected.to eq(0) }
      end
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

      # fixture has 1 build system requires and plus 1 dependencies exists

      its(:length) { is_expected.to eq(1) }

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

        # fixture has 1 build system requires and no dependencies or
        # optional dependencies exists

        its(:length) { is_expected.to eq(0) }
      end
    end

    context "with UV sources path dependencies" do
      subject(:dependencies) { parser.dependency_set.dependencies }

      let(:pyproject_fixture_name) { "uv_path_dependencies.toml" }

      # Mock the Python helper to include UV sources
      before do
        allow(Dependabot::SharedHelpers)
          .to receive(:run_helper_subprocess)
          .with(hash_including(function: "parse_pep621_dependencies"))
          .and_return([
            {
              "name" => "requests",
              "version" => nil,
              "markers" => nil,
              "file" => "pyproject.toml",
              "requirement" => ">=2.31.0",
              "extras" => []
            },
            {
              "name" => "protos",
              "version" => nil,
              "markers" => nil,
              "file" => "pyproject.toml",
              "requirement" => nil,
              "extras" => [],
              "path_dependency" => true,
              "path" => "../protos"
            },
            {
              "name" => "another-local",
              "version" => nil,
              "markers" => nil,
              "file" => "pyproject.toml",
              "requirement" => nil,
              "extras" => [],
              "path_dependency" => true,
              "path" => "./local-lib"
            }
          ])
      end

      its(:length) { is_expected.to eq(3) }

      describe "regular dependency from PEP 621" do
        subject(:dependency) { dependencies.find { |d| d.name == "requests" } }

        it "parses regular dependencies normally" do
          expect(dependency).to be_a(Dependabot::Dependency)
          expect(dependency.name).to eq("requests")
          expect(dependency.version).to be_nil
          expect(dependency.requirements).to eq([{
            requirement: ">=2.31.0",
            file: "pyproject.toml",
            source: nil,
            groups: ["dependencies"]
          }])
        end
      end

      describe "UV sources path dependency" do
        subject(:dependency) { dependencies.find { |d| d.name == "protos" } }

        it "includes UV sources path dependencies in the dependency set" do
          expect(dependency).to be_a(Dependabot::Dependency)
          expect(dependency.name).to eq("protos")
          expect(dependency.version).to be_nil
          expect(dependency.requirements).to eq([{
            requirement: nil,
            file: "pyproject.toml",
            source: nil,
            groups: ["dependencies"]
          }])
        end
      end

      describe "editable UV sources path dependency" do
        subject(:dependency) { dependencies.find { |d| d.name == "another-local" } }

        it "handles editable UV sources path dependencies" do
          expect(dependency).to be_a(Dependabot::Dependency)
          expect(dependency.name).to eq("another-local")
          expect(dependency.version).to be_nil
          expect(dependency.requirements).to eq([{
            requirement: nil,
            file: "pyproject.toml",
            source: nil,
            groups: ["dependencies"]
          }])
        end
      end
    end

    context "with mixed UV sources" do
      subject(:dependencies) { parser.dependency_set.dependencies }

      let(:pyproject_fixture_name) { "uv_mixed_sources.toml" }

      # Mock the Python helper to return only path dependencies from UV sources
      before do
        allow(Dependabot::SharedHelpers)
          .to receive(:run_helper_subprocess)
          .with(hash_including(function: "parse_pep621_dependencies"))
          .and_return([
            {
              "name" => "requests",
              "version" => nil,
              "markers" => nil,
              "file" => "pyproject.toml",
              "requirement" => ">=2.31.0",
              "extras" => []
            },
            {
              "name" => "local-package",
              "version" => nil,
              "markers" => nil,
              "file" => "pyproject.toml",
              "requirement" => nil,
              "extras" => [],
              "path_dependency" => true,
              "path" => "./local-package"
            }
            # Note: git-package, registry-package, url-package are NOT included
            # as they are not path dependencies
          ])
      end

      its(:length) { is_expected.to eq(2) }

      it "only includes path-based UV sources, not git/url/registry sources" do
        dependency_names = dependencies.map(&:name)
        expect(dependency_names).to include("local-package")
        expect(dependency_names).not_to include("git-package")
        expect(dependency_names).not_to include("registry-package")
        expect(dependency_names).not_to include("url-package")
      end

      describe "the path dependency from UV sources" do
        subject(:dependency) { dependencies.find { |d| d.name == "local-package" } }

        it "has correct path dependency details" do
          expect(dependency).to be_a(Dependabot::Dependency)
          expect(dependency.name).to eq("local-package")
          expect(dependency.version).to be_nil
          expect(dependency.requirements).to eq([{
            requirement: nil,
            file: "pyproject.toml",
            source: nil,
            groups: ["dependencies"]
          }])
        end
      end
    end
  end
end
