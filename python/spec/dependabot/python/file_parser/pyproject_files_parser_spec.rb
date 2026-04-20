# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency_file"
require "dependabot/python"

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

      context "with a git requirement with tag" do
        let(:pyproject_fixture_name) { "git_dependency_with_tag.toml" }

        it "includes git dependency with tag" do
          expect(dependencies.map(&:name)).to include("fastapi")
        end

        describe "the git dependency with tag" do
          subject(:dependency) { dependencies.find { |d| d.name == "fastapi" } }

          it "has the right details" do
            expect(dependency).to be_a(Dependabot::Dependency)
            expect(dependency.name).to eq("fastapi")
            expect(dependency.version).to be_nil
            expect(dependency.requirements).to eq(
              [{
                requirement: nil,
                file: "pyproject.toml",
                groups: ["dependencies"],
                source: {
                  type: "git",
                  url: "https://github.com/tiangolo/fastapi",
                  ref: "0.110.0",
                  branch: nil
                }
              }]
            )
          end
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

        it "includes production dependencies" do
          expect(dependencies.map(&:name)).to include("requests")
          expect(dependencies.map(&:name)).to include("geopy")
        end

        it "includes dev dependencies" do
          expect(dependencies.map(&:name)).to include("pytest")
          expect(dependencies.map(&:name)).to include("black")
        end

        it "excludes the python dependency" do
          expect(dependencies.map(&:name)).not_to include("python")
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
        subject(:dep) { dependencies.find { |d| d.name == "click" } }

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

      describe "Poetry v2 lock file groups and markers" do
        it "includes packages with groups field" do
          # appdirs has groups = ["dev"] in the v2 lock file
          appdirs = dependencies.find { |d| d.name == "appdirs" }
          expect(appdirs).to be_a(Dependabot::Dependency)
          expect(appdirs.version).to eq("1.4.3")
        end

        it "includes packages belonging to multiple groups" do
          # certifi has groups = ["main", "dev"] in the v2 lock file
          certifi = dependencies.find { |d| d.name == "certifi" }
          expect(certifi).to be_a(Dependabot::Dependency)
          expect(certifi.version).to eq("2018.4.16")
        end

        it "includes packages with markers field" do
          # colorama has markers = 'sys_platform == "win32"' in the v2 lock file
          colorama = dependencies.find { |d| d.name == "colorama" }
          expect(colorama).to be_a(Dependabot::Dependency)
          expect(colorama.version).to eq("0.3.9")
        end

        it "preserves groups and markers in parsed TOML" do
          parsed = TomlRB.parse(poetry_lock_body)
          packages = parsed.fetch("package", [])

          colorama_pkg = packages.find { |p| p["name"] == "colorama" }
          expect(colorama_pkg["groups"]).to eq(["dev"])
          expect(colorama_pkg["markers"]).to eq("sys_platform == \"win32\"")

          certifi_pkg = packages.find { |p| p["name"] == "certifi" }
          expect(certifi_pkg["groups"]).to eq(%w(main dev))
          expect(certifi_pkg).not_to have_key("markers")

          appdirs_pkg = packages.find { |p| p["name"] == "appdirs" }
          expect(appdirs_pkg["groups"]).to eq(["dev"])
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

    context "with a group that has no dependencies key" do
      subject(:dependency_names) { dependencies.map(&:name) }

      let(:pyproject_fixture_name) { "poetry_group_without_dependencies.toml" }

      it "does not raise and parses the other dependencies" do
        expect(dependency_names).to include("requests")
        expect(dependency_names).to include("pytest")
      end
    end

    context "with package specify source" do
      subject(:dependency) { dependencies.find { |f| f.name == "black" } }

      let(:pyproject_fixture_name) { "package_specify_source.toml" }

      it "resolves string registry sources to hashes with type and url" do
        # String sources (registry name references) are resolved to their definitions
        # from [[tool.poetry.source]] to create proper hash sources
        expect(dependency.requirements[0][:source]).to be_nil # No source def in this fixture
      end
    end

    context "with private secondary source" do
      subject(:dependency) { dependencies.find { |f| f.name == "luigi" } }

      let(:pyproject_fixture_name) { "private_secondary_source.toml" }

      it "resolves string registry sources to hashes with type and url" do
        # String source "custom" should be resolved to the source definition
        expect(dependency.requirements[0][:source]).to eq(
          {
            type: "registry",
            url: "https://some.internal.registry.com/pypi/",
            name: "custom"
          }
        )
      end
    end

    describe "Poetry v2 fixtures" do
      let(:files) { [pyproject, poetry_lock] }
      let(:poetry_lock) do
        Dependabot::DependencyFile.new(
          name: "poetry.lock",
          content: fixture("poetry_locks", poetry_lock_fixture_name)
        )
      end

      context "with a PEP 621 only project (project.dependencies)" do
        let(:pyproject_fixture_name) { "poetry_v2_pep621_only.toml" }
        let(:poetry_lock_fixture_name) { "poetry_v2_pep621_only.lock" }

        it "parses PEP 621 project.dependencies" do
          names = dependencies.map(&:name)
          expect(names).to include("requests", "urllib3")
        end

        it "marks PEP 621 deps with the project.dependencies group" do
          requests = dependencies.find { |d| d.name == "requests" }
          expect(requests.requirements.first[:groups]).to eq(["dependencies"])
        end

        it "parses the v2 lock file metadata" do
          parsed = TomlRB.parse(fixture("poetry_locks", poetry_lock_fixture_name))
          expect(parsed.dig("metadata", "lock-version")).to eq("2.0")
        end

        it "preserves the requirement strings from project.dependencies" do
          requests = dependencies.find { |d| d.name == "requests" }
          urllib3 = dependencies.find { |d| d.name == "urllib3" }
          expect(requests.requirements.first[:requirement]).to eq("<3.0,>=2.28.0")
          expect(urllib3.requirements.first[:requirement]).to eq(">=1.26.0")
        end

        it "requires poetry-core>=2.0 as the build backend" do
          parsed = TomlRB.parse(fixture("pyproject_files", pyproject_fixture_name))
          expect(parsed.dig("build-system", "requires")).to eq(["poetry-core>=2.0.0,<3.0.0"])
          expect(parsed.dig("build-system", "build-backend")).to eq("poetry.core.masonry.api")
        end

        it "does not include tool.poetry in the manifest" do
          parsed = TomlRB.parse(fixture("pyproject_files", pyproject_fixture_name))
          expect(parsed.dig("tool", "poetry")).to be_nil
        end
      end

      context "with a hybrid PEP 621 + tool.poetry enrichment project" do
        let(:pyproject_fixture_name) { "poetry_v2_hybrid.toml" }
        let(:poetry_lock_fixture_name) { "poetry_v2_hybrid.lock" }

        it "parses dependencies declared in both sections without duplication" do
          requests_deps = dependencies.select { |d| d.name == "requests" }
          flask_deps = dependencies.select { |d| d.name == "flask" }
          expect(requests_deps.length).to eq(1)
          expect(flask_deps.length).to eq(1)
        end

        it "resolves locked versions from the v2 lock file" do
          requests = dependencies.find { |d| d.name == "requests" }
          flask = dependencies.find { |d| d.name == "flask" }
          expect(requests.version).to eq("2.31.0")
          expect(flask.version).to eq("3.0.2")
        end

        it "preserves private source enrichment from tool.poetry" do
          parsed = TomlRB.parse(fixture("pyproject_files", pyproject_fixture_name))
          sources = parsed.dig("tool", "poetry", "source")
          expect(sources).to be_an(Array)
          expect(sources.first["name"]).to eq("private-source")
          expect(sources.first["url"]).to eq("https://private.example.com/simple")
          expect(sources.first["priority"]).to eq("supplemental")
        end

        it "preserves extras enrichment from tool.poetry" do
          parsed = TomlRB.parse(fixture("pyproject_files", pyproject_fixture_name))
          flask_enrichment = parsed.dig("tool", "poetry", "dependencies", "flask")
          expect(flask_enrichment["extras"]).to eq(["async"])
        end

        it "includes transitive dependencies from the lock file" do
          names = dependencies.map(&:name)
          expect(names).to include("jinja2", "werkzeug", "markupsafe")
        end
      end

      context "with dynamic dependencies managed by Poetry" do
        let(:pyproject_fixture_name) { "poetry_v2_dynamic.toml" }
        let(:poetry_lock_fixture_name) { "poetry_v2_dynamic.lock" }

        it "sources dependencies from tool.poetry when project.dependencies is dynamic" do
          names = dependencies.map(&:name)
          expect(names).to include("requests", "django")
        end

        it "resolves locked versions from the v2 lock file" do
          django = dependencies.find { |d| d.name == "django" }
          expect(django.version).to eq("5.0.3")
        end

        it "declares dynamic in project metadata" do
          parsed = TomlRB.parse(fixture("pyproject_files", pyproject_fixture_name))
          expect(parsed.dig("project", "dynamic")).to eq(["dependencies"])
        end

        it "does not duplicate deps between project and tool.poetry" do
          requests_deps = dependencies.select { |d| d.name == "requests" }
          django_deps = dependencies.select { |d| d.name == "django" }
          expect(requests_deps.length).to eq(1)
          expect(django_deps.length).to eq(1)
        end

        it "includes transitive django dependencies from the lock file" do
          names = dependencies.map(&:name)
          expect(names).to include("asgiref", "sqlparse")
        end
      end

      context "with a requires-poetry constraint" do
        let(:pyproject_fixture_name) { "poetry_v2_requires_poetry.toml" }
        let(:poetry_lock_fixture_name) { "poetry_v2_requires_poetry.lock" }

        it "parses dependencies without raising on the requires-poetry key" do
          expect { parser.dependency_set }.not_to raise_error
          expect(dependencies.map(&:name)).to include("requests", "click")
        end

        it "preserves the requires-poetry metadata in the TOML" do
          parsed = TomlRB.parse(fixture("pyproject_files", pyproject_fixture_name))
          expect(parsed.dig("tool", "poetry", "requires-poetry")).to eq(">=2.0")
        end

        it "resolves click to the locked version" do
          click = dependencies.find { |d| d.name == "click" }
          expect(click.version).to eq("8.1.7")
        end
      end

      context "with requires-plugins declared" do
        let(:pyproject_fixture_name) { "poetry_v2_requires_plugins.toml" }
        let(:poetry_lock_fixture_name) { "poetry_v2_requires_plugins.lock" }

        it "parses dependencies without raising on requires-plugins" do
          expect { parser.dependency_set }.not_to raise_error
          expect(dependencies.map(&:name)).to include("requests", "flask")
        end

        it "preserves the requires-plugins metadata in the TOML" do
          parsed = TomlRB.parse(fixture("pyproject_files", pyproject_fixture_name))
          plugins = parsed.dig("tool", "poetry", "requires-plugins")
          expect(plugins).to include("poetry-plugin-export")
        end

        it "preserves plugin version constraints" do
          parsed = TomlRB.parse(fixture("pyproject_files", pyproject_fixture_name))
          plugins = parsed.dig("tool", "poetry", "requires-plugins")
          expect(plugins["poetry-plugin-export"]).to eq(">=1.8.0")
        end

        it "does not include poetry plugins as project dependencies" do
          names = dependencies.map(&:name)
          expect(names).not_to include("poetry-plugin-export")
        end
      end

      context "with package-mode = false" do
        let(:pyproject_fixture_name) { "poetry_v2_package_mode_false.toml" }
        let(:poetry_lock_fixture_name) { "poetry_v2_package_mode_false.lock" }

        it "parses dependencies without requiring project metadata" do
          expect { parser.dependency_set }.not_to raise_error
          expect(dependencies.map(&:name)).to include("requests", "click")
        end

        it "preserves package-mode = false in the TOML" do
          parsed = TomlRB.parse(fixture("pyproject_files", pyproject_fixture_name))
          expect(parsed.dig("tool", "poetry", "package-mode")).to be(false)
        end

        it "still resolves locked versions" do
          requests = dependencies.find { |d| d.name == "requests" }
          expect(requests.version).to eq("2.31.0")
        end
      end

      context "with a v2 lock file containing groups and markers" do
        let(:pyproject_fixture_name) { "poetry_v2_groups_markers.toml" }
        let(:poetry_lock_fixture_name) { "poetry_v2_groups_markers.lock" }

        it "parses packages belonging to the main group" do
          requests = dependencies.find { |d| d.name == "requests" }
          expect(requests).to be_a(Dependabot::Dependency)
          expect(requests.version).to eq("2.31.0")
        end

        it "parses packages belonging to the dev group" do
          black = dependencies.find { |d| d.name == "black" }
          pytest = dependencies.find { |d| d.name == "pytest" }
          expect(black.version).to eq("24.2.0")
          expect(pytest.version).to eq("8.0.2")
        end

        it "parses packages belonging to the docs group" do
          sphinx = dependencies.find { |d| d.name == "sphinx" }
          expect(sphinx.version).to eq("7.2.6")
        end

        it "parses packages belonging to multiple groups" do
          parsed = TomlRB.parse(fixture("poetry_locks", poetry_lock_fixture_name))
          colorama_pkg = parsed["package"].find { |p| p["name"] == "colorama" }
          expect(colorama_pkg["groups"]).to eq(%w(main dev))
        end

        it "preserves markers on packages that declare them" do
          parsed = TomlRB.parse(fixture("poetry_locks", poetry_lock_fixture_name))
          tomli_pkg = parsed["package"].find { |p| p["name"] == "tomli" }
          expect(tomli_pkg["markers"]).to eq("python_version < \"3.11\"")

          colorama_pkg = parsed["package"].find { |p| p["name"] == "colorama" }
          expect(colorama_pkg["markers"]).to eq("sys_platform == \"win32\"")
        end

        it "preserves [dependency-groups] in the manifest" do
          parsed = TomlRB.parse(fixture("pyproject_files", pyproject_fixture_name))
          groups = parsed["dependency-groups"]
          expect(groups["dev"]).to include("pytest>=7.0", "black>=23.0")
          expect(groups["docs"]).to eq(["sphinx>=6.0"])
        end

        it "parses transitive dependencies of dev group packages" do
          names = dependencies.map(&:name)
          expect(names).to include("pathspec", "platformdirs", "packaging")
        end

        it "includes conditional main dependencies with markers" do
          colorama = dependencies.find { |d| d.name == "colorama" }
          expect(colorama).to be_a(Dependabot::Dependency)
        end
      end

      context "with project.optional-dependencies" do
        let(:pyproject_fixture_name) { "poetry_v2_optional_deps.toml" }
        let(:poetry_lock_fixture_name) { "poetry_v2_optional_deps.lock" }

        it "parses the main project.dependencies" do
          requests = dependencies.find { |d| d.name == "requests" }
          expect(requests).to be_a(Dependabot::Dependency)
          expect(requests.version).to eq("2.31.0")
        end

        it "parses project.optional-dependencies extras" do
          names = dependencies.map(&:name)
          expect(names).to include("pysocks", "cryptography")
        end

        it "preserves the optional flag and extras markers in the v2 lock" do
          parsed = TomlRB.parse(fixture("poetry_locks", poetry_lock_fixture_name))
          pysocks_pkg = parsed["package"].find { |p| p["name"] == "pysocks" }
          expect(pysocks_pkg["optional"]).to be(true)
          expect(pysocks_pkg["markers"]).to eq("extra == \"socks\"")

          crypto_pkg = parsed["package"].find { |p| p["name"] == "cryptography" }
          expect(crypto_pkg["optional"]).to be(true)
          expect(crypto_pkg["markers"]).to eq("extra == \"security\"")
        end

        it "preserves optional-dependency extras groupings in the manifest" do
          parsed = TomlRB.parse(fixture("pyproject_files", pyproject_fixture_name))
          optional = parsed.dig("project", "optional-dependencies")
          expect(optional["socks"]).to eq(["PySocks>=1.5.6,!=1.5.7"])
          expect(optional["security"]).to eq(["cryptography>=41.0.0"])
        end

        it "parses transitive deps for optional extras" do
          names = dependencies.map(&:name)
          # cffi / pycparser are transitive deps of cryptography
          expect(names).to include("cffi", "pycparser")
        end
      end

      context "with a legacy poetry-core>=1.0 build system" do
        let(:pyproject_fixture_name) { "poetry_v2_legacy_build_system.toml" }
        let(:poetry_lock_fixture_name) { "poetry_v2_legacy_build_system.lock" }

        it "parses dependencies with the legacy build backend" do
          requests = dependencies.find { |d| d.name == "requests" }
          expect(requests).to be_a(Dependabot::Dependency)
        end

        it "declares the legacy poetry-core>=1.0 build-system requires" do
          parsed = TomlRB.parse(fixture("pyproject_files", pyproject_fixture_name))
          requires = parsed.dig("build-system", "requires")
          expect(requires).to eq(["poetry-core>=1.0.0"])
        end

        it "emits a v2-format lock file despite the legacy build backend" do
          parsed = TomlRB.parse(fixture("poetry_locks", poetry_lock_fixture_name))
          expect(parsed.dig("metadata", "lock-version")).to eq("2.0")
          expect(parsed["package"]).to all(have_key("groups"))
        end
      end

      describe "cross-fixture invariants" do
        %w(
          poetry_v2_pep621_only
          poetry_v2_hybrid
          poetry_v2_dynamic
          poetry_v2_requires_poetry
          poetry_v2_requires_plugins
          poetry_v2_package_mode_false
          poetry_v2_groups_markers
          poetry_v2_optional_deps
          poetry_v2_legacy_build_system
        ).each do |name|
          context "with the #{name} fixture" do
            let(:pyproject_fixture_name) { "#{name}.toml" }
            let(:poetry_lock_fixture_name) { "#{name}.lock" }

            it "uses lock-version 2.0" do
              parsed = TomlRB.parse(fixture("poetry_locks", poetry_lock_fixture_name))
              expect(parsed.dig("metadata", "lock-version")).to eq("2.0")
            end

            it "declares a non-empty groups array on every package" do
              parsed = TomlRB.parse(fixture("poetry_locks", poetry_lock_fixture_name))
              parsed["package"].each do |pkg|
                expect(pkg["groups"]).to be_an(Array), "#{pkg['name']} is missing groups"
                expect(pkg["groups"]).not_to be_empty
              end
            end

            it "parses the manifest as valid TOML" do
              expect { TomlRB.parse(fixture("pyproject_files", pyproject_fixture_name)) }
                .not_to raise_error
            end
          end
        end
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
            groups: ["dependencies"],
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

    context "with optional dependencies only" do
      subject(:dependencies) { parser.dependency_set.dependencies }

      let(:pyproject_fixture_name) { "optional_dependencies_only.toml" }

      its(:length) { is_expected.to be > 0 }
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

      context "with optional dependencies only" do
        subject(:dependencies) { parser.dependency_set.dependencies }

        let(:pyproject_fixture_name) { "pyproject_1_0_0_optional_deps.toml" }

        its(:length) { is_expected.to be > 0 }
      end

      context "with PEP 621 and Poetry configuration" do
        subject(:dependencies) { parser.dependency_set.dependencies }

        let(:pyproject_fixture_name) { "pep621_with_poetry.toml" }

        its(:length) { is_expected.to eq(2) }

        it "has the correct dependencies with requirement types" do
          expect(dependencies.map(&:name)).to contain_exactly("fastapi", "pydantic")

          fastapi = dependencies.find { |d| d.name == "fastapi" }
          expect(fastapi.version).to eq("0.115.5")
          expect(fastapi.requirements.first[:groups]).to eq(["dependencies"])

          pydantic = dependencies.find { |d| d.name == "pydantic" }
          expect(pydantic.version).to eq("2.8.2")
          expect(pydantic.requirements.first[:groups]).to eq(["dependencies"])
        end
      end

      context "with dynamic dependencies in Poetry project" do
        subject(:dependencies) { parser.dependency_set.dependencies }

        let(:pyproject_fixture_name) { "pep621_dynamic_dependencies.toml" }

        it "skips PEP 621 dependencies when dependencies is dynamic" do
          dep_names = dependencies.map(&:name)
          # Poetry deps are parsed but PEP 621 [project] dependencies are not
          # since they are marked as dynamic and managed by Poetry
          expect(dep_names).to include("requests", "django")
          dependencies.each do |dep|
            expect(dep.requirements.first[:groups]).to eq(["dependencies"])
          end
        end

        it "does not duplicate deps from PEP 621 when dynamic" do
          # Each dep should appear only once (from Poetry), not duplicated from [project].dependencies
          requests_deps = dependencies.select { |d| d.name == "requests" }
          django_deps = dependencies.select { |d| d.name == "django" }
          expect(requests_deps.length).to eq(1)
          expect(django_deps.length).to eq(1)
        end
      end

      context "with dynamic optional-dependencies in Poetry project" do
        subject(:dependencies) { parser.dependency_set.dependencies }

        let(:pyproject_fixture_name) { "pep621_dynamic_optional_dependencies.toml" }

        it "skips PEP 621 optional deps but keeps non-dynamic deps" do
          dep_names = dependencies.map(&:name)
          # requests comes from [project] dependencies (not dynamic)
          expect(dep_names).to include("requests")
          req = dependencies.find { |d| d.name == "requests" }
          expect(req.requirements.first[:groups]).to eq(["dependencies"])
        end

        it "does not duplicate optional deps from PEP 621 when dynamic" do
          pysocks_deps = dependencies.select { |d| d.name == "pysocks" }
          # Should only appear once (from Poetry), not duplicated from PEP 621
          expect(pysocks_deps.length).to eq(1)
        end
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
  end
end
