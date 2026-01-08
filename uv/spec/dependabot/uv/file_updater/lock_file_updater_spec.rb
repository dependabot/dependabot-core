# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency"
require "dependabot/dependency_file"
require "dependabot/uv/file_updater/lock_file_updater"
require "dependabot/shared_helpers"

RSpec.describe Dependabot::Uv::FileUpdater::LockFileUpdater do
  let(:updater) do
    described_class.new(
      dependencies: dependencies,
      dependency_files: dependency_files,
      credentials: credentials,
      index_urls: index_urls
    )
  end

  let(:dependencies) { [dependency] }
  let(:credentials) do
    [Dependabot::Credential.new(
      {
        "type" => "git_source",
        "host" => "github.com",
        "username" => "x-access-token",
        "password" => "token"
      }
    )]
  end
  let(:index_urls) { [] }

  let(:dependency) do
    Dependabot::Dependency.new(
      name: "requests",
      version: "2.23.0",
      requirements: [{
        file: "pyproject.toml",
        requirement: "==2.23.0",
        groups: [],
        source: nil
      }],
      previous_requirements: [{
        file: "pyproject.toml",
        requirement: ">=2.31.0",
        groups: [],
        source: nil
      }],
      previous_version: "2.32.3",
      package_manager: "uv"
    )
  end

  let(:pyproject_content) { fixture("pyproject_files", "uv_simple.toml") }
  let(:lockfile_content) { fixture("uv_locks", "simple.lock") }

  let(:pyproject_file) do
    Dependabot::DependencyFile.new(
      name: "pyproject.toml",
      content: pyproject_content
    )
  end

  let(:lockfile) do
    Dependabot::DependencyFile.new(
      name: "uv.lock",
      content: lockfile_content
    )
  end

  let(:dependency_files) { [pyproject_file, lockfile] }

  describe "#updated_dependency_files" do
    subject(:updated_files) { updater.updated_dependency_files }

    before do
      allow(updater).to receive_messages(
        updated_pyproject_content: updated_pyproject_content,
        updated_lockfile_content_for: updated_lockfile_content
      )
    end

    let(:updated_pyproject_content) do
      pyproject_content.sub(
        "requests>=2.31.0",
        "requests==2.23.0"
      )
    end

    let(:updated_lockfile_content) do
      lockfile_content.sub(
        /name = "requests"\nversion = "2\.32\.3"/, # rubocop:disable Style/RedundantRegexpArgument
        'name = "requests"\nversion = "2.23.0"'
      )
    end

    it "returns updated pyproject.toml and lockfile" do
      expect(updated_files.count).to eq(2)

      pyproject = updated_files.find { |f| f.name == "pyproject.toml" }
      expect(pyproject.content).to include("requests==2.23.0")

      lockfile = updated_files.find { |f| f.name == "uv.lock" }
      expect(lockfile.content).to include('name = "requests"')
      expect(lockfile.content).to include('version = "2.23.0"')
    end

    context "with platform specific environment markers" do
      let(:pyproject_content) do
        <<~TOML
          [project]
          name = "example"
          version = "1.0.0"
          dependencies = [
            "pyad>=0.6.0 ; sys_platform == 'win32'",
            "pywin32>=310; sys_platform == 'win32'",
            "colorama>=0.4.6"
          ]
        TOML
      end

      let(:lockfile_content) { "original lock content" }

      let(:dependency) do
        Dependabot::Dependency.new(
          name: "pywin32",
          version: "311",
          requirements: [{
            file: "pyproject.toml",
            requirement: ">=311",
            groups: [],
            source: nil
          }],
          previous_requirements: [{
            file: "pyproject.toml",
            requirement: ">=310",
            groups: [],
            source: nil
          }],
          package_manager: "uv"
        )
      end

      let(:updated_lockfile_content) { "updated lock content" }

      before do
        allow(updater).to receive(:updated_pyproject_content).and_call_original
        allow(updater).to receive(:updated_lockfile_content_for).and_return("updated lock content")
      end

      it "preserves environment markers for all dependencies" do
        pyproject = updated_files.find { |f| f.name == "pyproject.toml" }

        expect(pyproject.content)
          .to include("pyad>=0.6.0 ; sys_platform == 'win32'")
        expect(pyproject.content)
          .to include("pywin32>=311; sys_platform == 'win32'")
      end
    end

    context "when the lockfile doesn't change" do
      before do
        allow(updater).to receive(:updated_lockfile_content).and_return(lockfile_content)
      end

      it "raises an error" do
        expect { updated_files }.to raise_error("Expected lockfile to change!")
      end
    end

    context "when UV dependency resolution fails" do
      before do
        allow(updater).to receive(:updated_lockfile_content_for).and_call_original
        allow(updater).to receive(:run_command).and_raise(error)
      end

      context "with 'No solution found when resolving dependencies' error" do
        let(:error) do
          Dependabot::SharedHelpers::HelperSubprocessFailed.new(
            message: uv_dependency_conflict_error,
            error_context: {}
          )
        end

        let(:uv_dependency_conflict_error) do
          <<~ERROR
            Using CPython 3.12.11 interpreter at: /usr/local/.pyenv/versions/3.12.11/bin/python3.12
            × No solution found when resolving dependencies:
            ╰─▶ Because awscli==1.42.35 depends on botocore==1.40.35 and boto3==1.40.51
                depends on botocore>=1.40.51,<1.41.0, we can conclude that
                awscli==1.42.35 and boto3==1.40.51 are incompatible.
                And because your project depends on awscli==1.42.35 and boto3==1.40.51,
                we can conclude that your project's requirements are unsatisfiable.
          ERROR
        end

        it "raises a DependencyFileNotResolvable error with the detailed UV error message" do
          expect { updated_files }.to raise_error(Dependabot::DependencyFileNotResolvable) do |error|
            expect(error.message).to include("No solution found when resolving dependencies")
            expect(error.message).to include("Because awscli==1.42.35 depends on botocore==1.40.35")
            expect(error.message).to include("we can conclude that your project's requirements are unsatisfiable")
          end
        end
      end

      context "with RESOLUTION_IMPOSSIBLE_ERROR error" do
        let(:error) do
          Dependabot::SharedHelpers::HelperSubprocessFailed.new(
            message: "ResolutionImpossible: Could not find a version that satisfies the requirement",
            error_context: {}
          )
        end

        it "raises a DependencyFileNotResolvable error with the detailed UV error message" do
          expect { updated_files }.to raise_error(Dependabot::DependencyFileNotResolvable, /ResolutionImpossible/)
        end
      end

      context "with 'Failed to build' error" do
        let(:error) do
          Dependabot::SharedHelpers::HelperSubprocessFailed.new(
            message: uv_build_failed_error,
            error_context: {}
          )
        end

        let(:uv_build_failed_error) do
          <<~ERROR
            Using CPython 3.12.11 interpreter at: /usr/local/.pyenv/versions/3.12.11/bin/python3.12
            × Failed to build `pygraph @
            │ file://dependabot_tmp_dir`
            ├─▶ The build backend returned an error
            ╰─▶ Call to `hatchling.build.prepare_metadata_for_build_editable` failed
                (exit status: 1)

                [stderr]
                Traceback (most recent call last):
                  File "<string>", line 14, in <module>
                LookupError: Error getting the version from source
                `vcs`: setuptools-scm was unable to detect version for
                dependabot_tmp_dir.

                Make sure you're either building from a fully intact git repository
                or PyPI tarballs. Most other sources (such as GitHub's tarballs, a git
                checkout without the .git folder) don't contain the necessary metadata
                and will not work.
          ERROR
        end

        it "raises a DependencyFileNotResolvable error with the detailed UV error message" do
          expect { updated_files }.to raise_error(Dependabot::DependencyFileNotResolvable) do |error|
            expect(error.message).to include("Failed to build")
            expect(error.message).to include("setuptools-scm was unable to detect version")
            expect(error.message).to include("Make sure you're either building from a fully intact git repository")
          end
        end
      end

      context "when error is unrecognized" do
        let(:error) do
          Dependabot::SharedHelpers::HelperSubprocessFailed.new(
            message: "Some other error",
            error_context: {}
          )
        end

        it "raises the original error" do
          expect { updated_files }.to raise_error(Dependabot::SharedHelpers::HelperSubprocessFailed, /Some other error/)
        end
      end
    end

    context "with pyproject preparation" do
      before do
        pyproject_preparer = instance_double(Dependabot::Uv::FileUpdater::PyprojectPreparer)

        allow(Dependabot::Uv::FileUpdater::PyprojectPreparer).to receive(:new)
          .and_return(pyproject_preparer)

        allow(pyproject_preparer).to receive_messages(
          update_python_requirement: "python requirement updated content",
          sanitize: "sanitized content"
        )

        # Mock the command execution
        allow(updater).to receive(:run_command).and_return(true)
        allow(File).to receive(:read).with("uv.lock").and_return(updated_lockfile_content)
      end

      it "prepares the pyproject file correctly" do
        expect(Dependabot::Uv::FileUpdater::PyprojectPreparer).to receive(:new)
        updated_files
      end
    end

    context "with TOML parsing" do
      let(:lockfile_content) { fixture("uv_locks", "minimal.lock") }
      let(:updated_lockfile_content) { fixture("uv_locks", "minimal_updated.lock") }

      # Simulate a change to the python version in the updated lockfile
      let(:modified_lockfile_content) do
        content = updated_lockfile_content.dup
        content.sub('requires-python = ">=3.9"', 'requires-python = ">=3.8"')
      end

      before do
        allow(updater).to receive(:updated_lockfile_content_for).and_return(modified_lockfile_content)
      end

      it "preserves the original requires-python value and updates the package section" do
        updated_lock = updated_files.find { |f| f.name == "uv.lock" }
        expect(updated_lock.content).to include('requires-python = ">=3.9"')
        expect(updated_lock.content).to include('name = "requests"')
        expect(updated_lock.content).to include('version = "2.32.3"')
        expect(updated_lock.content).to include("requests-2.32.3.tar.gz")
        expect(updated_lock.content).to include("requests-2.32.3-py3-none-any.whl")

        expect(updated_lock.content).not_to include('requires-python = ">=3.8"')
        expect(updated_lock.content).not_to include('version = "2.31.0"')
        expect(updated_lock.content).not_to include("requests-2.31.0.tar.gz")
        expect(updated_lock.content).not_to include("requests-2.31.0-py3-none-any.whl")
      end
    end

    context "when updating a build-system-only dependency" do
      let(:pyproject_content) { fixture("pyproject_files", "build_system_pinned.toml") }
      let(:lockfile_content) { fixture("uv_locks", "build_system_pinned.lock") }

      let(:dependency) do
        Dependabot::Dependency.new(
          name: "hatchling",
          version: "1.28.0",
          requirements: [{
            file: "pyproject.toml",
            requirement: "==1.28.0",
            groups: ["build-system"],
            source: nil
          }],
          previous_requirements: [{
            file: "pyproject.toml",
            requirement: "==1.27",
            groups: ["build-system"],
            source: nil
          }],
          previous_version: "1.27",
          package_manager: "uv"
        )
      end

      it "updates only pyproject.toml, not the lockfile" do
        allow(updater).to receive(:updated_pyproject_content).and_return(
          pyproject_content.sub('"hatchling==1.27"', '"hatchling==1.28.0"')
        )

        updated_dependency_files = updater.updated_dependency_files

        # Should update pyproject.toml
        pyproj = updated_dependency_files.find { |f| f.name == "pyproject.toml" }
        expect(pyproj).not_to be_nil
        expect(pyproj.content).to include('"hatchling==1.28.0"')

        # Should NOT include lockfile in updated files
        expect(updated_dependency_files.map(&:name)).not_to include("uv.lock")
      end
    end

    context "when updating a regular dependency" do
      let(:pyproject_content) { fixture("pyproject_files", "uv_simple.toml") }
      let(:lockfile_content) { fixture("uv_locks", "simple.lock") }

      let(:dependency) do
        Dependabot::Dependency.new(
          name: "requests",
          version: "2.33.0",
          requirements: [{
            file: "pyproject.toml",
            requirement: ">=2.33.0",
            groups: [],
            source: nil
          }],
          previous_requirements: [{
            file: "pyproject.toml",
            requirement: ">=2.31.0",
            groups: [],
            source: nil
          }],
          previous_version: "2.32.3",
          package_manager: "uv"
        )
      end

      it "updates both pyproject.toml and lockfile" do
        updated_lockfile = lockfile_content.sub('version = "2.32.3"', 'version = "2.33.0"')
        updated_pyproject = pyproject_content.sub("requests>=2.31.0", "requests>=2.33.0")

        allow(updater).to receive_messages(
          updated_pyproject_content: updated_pyproject,
          updated_lockfile_content_for: updated_lockfile
        )

        updated_dependency_files = updater.updated_dependency_files

        # Should update both files
        expect(updated_dependency_files.map(&:name)).to include("pyproject.toml")
        expect(updated_dependency_files.map(&:name)).to include("uv.lock")

        pyproj = updated_dependency_files.find { |f| f.name == "pyproject.toml" }
        expect(pyproj.content).to include("requests>=2.33.0")

        lockfile = updated_dependency_files.find { |f| f.name == "uv.lock" }
        expect(lockfile.content).to include('version = "2.33.0"')
      end
    end
  end

  describe "with a requirements.txt or requirements.in file only" do
    let(:dependencies) do
      [
        Dependabot::Dependency.new(
          name: "requests",
          version: "2.23.0",
          requirements: [{
            file: "requirements.txt",
            requirement: "==2.23.0",
            groups: [],
            source: nil
          }],
          previous_requirements: [{
            file: "requirements.txt",
            requirement: ">=2.31.0",
            groups: [],
            source: nil
          }],
          previous_version: "2.32.3",
          package_manager: "uv"
        )
      ]
    end
    let(:dependency_files) do
      [
        Dependabot::DependencyFile.new(
          name: "requirements.txt",
          content: fixture("requirements/uv_pip_compile_requests.txt")
        ),
        Dependabot::DependencyFile.new(
          name: "requirements.in",
          content: fixture("pip_compile_files/requests.in")
        )
      ]
    end

    it "ignores the requirements file" do
      expect(updater.updated_dependency_files).to be_empty
    end
  end

  describe "#lock_index_options" do
    subject(:lock_index_options) { updater.send(:lock_index_options) }

    let(:credentials) do
      [
        Dependabot::Credential.new(
          {
            "type" => "python_index",
            "index-url" => "https://example.com/simple",
            "token" => "token",
            "replaces-base" => false
          }
        ),
        Dependabot::Credential.new(
          {
            "type" => "python_index",
            "index-url" => "https://another.com/simple",
            "token" => "another_token",
            "replaces-base" => true
          }
        )
      ]
    end

    it "matches authed urls to correct option index flags" do
      expect(lock_index_options).to include("--default-index https://another_token@another.com/simple")
      expect(lock_index_options).to include("--index https://token@example.com/simple")
    end

    context "with an explicit index in pyproject.toml" do
      let(:pyproject_content) { fixture("pyproject_files", "uv_explicit_index.toml") }

      let(:credentials) do
        [
          Dependabot::Credential.new(
            {
              "type" => "python_index",
              "index-url" => "https://private-pypi.example.com/simple",
              "token" => "secret_token",
              "replaces-base" => false
            }
          )
        ]
      end

      it "does not include --index flag for explicit indices" do
        options = lock_index_options.join(" ")
        expect(options).not_to include("--index")
        expect(options).not_to include("--default-index")
      end
    end

    context "with mixed explicit and non-explicit indices in pyproject.toml" do
      let(:pyproject_content) { fixture("pyproject_files", "uv_mixed_explicit_indices.toml") }

      let(:credentials) do
        [
          Dependabot::Credential.new(
            {
              "type" => "python_index",
              "index-url" => "https://private-pypi.example.com/simple",
              "token" => "explicit_token",
              "replaces-base" => false
            }
          ),
          Dependabot::Credential.new(
            {
              "type" => "python_index",
              "index-url" => "https://fallback-pypi.example.com/simple",
              "token" => "fallback_token",
              "replaces-base" => false
            }
          )
        ]
      end

      it "includes --index flag only for non-explicit indices" do
        options = lock_index_options.join(" ")
        expect(options).not_to include("https://explicit_token@private-pypi.example.com/simple")
        expect(options).to include("--index https://fallback_token@fallback-pypi.example.com/simple")
      end
    end

    context "with a non-explicit index in pyproject.toml" do
      let(:pyproject_content) { fixture("pyproject_files", "uv_non_explicit_index.toml") }

      let(:credentials) do
        [
          Dependabot::Credential.new(
            {
              "type" => "python_index",
              "index-url" => "https://private-pypi.example.com/simple",
              "token" => "token",
              "replaces-base" => false
            }
          )
        ]
      end

      it "includes --index flag for non-explicit indices" do
        expect(lock_index_options).to include("--index https://token@private-pypi.example.com/simple")
      end
    end

    context "with replaces-base credential matching an explicit index" do
      let(:pyproject_content) { fixture("pyproject_files", "uv_explicit_index.toml") }

      let(:credentials) do
        [
          Dependabot::Credential.new(
            {
              "type" => "python_index",
              "index-url" => "https://private-pypi.example.com/simple",
              "token" => "secret_token",
              "replaces-base" => true
            }
          )
        ]
      end

      it "still uses --default-index when replaces-base is true, ignoring explicit flag" do
        expect(lock_index_options).to include("--default-index https://secret_token@private-pypi.example.com/simple")
      end
    end

    context "with credential URL not matching any pyproject.toml index" do
      let(:pyproject_content) { fixture("pyproject_files", "uv_explicit_index.toml") }

      let(:credentials) do
        [
          Dependabot::Credential.new(
            {
              "type" => "python_index",
              "index-url" => "https://unrelated-pypi.example.com/simple",
              "token" => "unrelated_token",
              "replaces-base" => false
            }
          )
        ]
      end

      it "includes --index flag for credentials not matching any configured index" do
        expect(lock_index_options).to include("--index https://unrelated_token@unrelated-pypi.example.com/simple")
      end
    end

    context "with URL matching that includes trailing slash differences" do
      let(:pyproject_content) { fixture("pyproject_files", "uv_explicit_index.toml") }

      let(:credentials) do
        [
          Dependabot::Credential.new(
            {
              "type" => "python_index",
              "index-url" => "https://private-pypi.example.com/simple/",
              "token" => "secret_token",
              "replaces-base" => false
            }
          )
        ]
      end

      it "matches URLs ignoring trailing slashes" do
        options = lock_index_options.join(" ")
        expect(options).not_to include("--index")
      end
    end
  end

  describe "#explicit_index_env_vars" do
    subject(:explicit_index_env_vars) { updater.send(:explicit_index_env_vars) }

    context "with an explicit index requiring authentication" do
      let(:pyproject_content) { fixture("pyproject_files", "uv_explicit_index.toml") }

      let(:credentials) do
        [
          Dependabot::Credential.new(
            {
              "type" => "python_index",
              "index-url" => "https://private-pypi.example.com/simple",
              "username" => "my_user",
              "password" => "my_password",
              "replaces-base" => false
            }
          )
        ]
      end

      it "returns environment variables for explicit index authentication" do
        expect(explicit_index_env_vars).to include(
          "UV_INDEX_COMPANY_PYPI_USERNAME" => "my_user",
          "UV_INDEX_COMPANY_PYPI_PASSWORD" => "my_password"
        )
      end
    end

    context "with an explicit index using token authentication" do
      let(:pyproject_content) { fixture("pyproject_files", "uv_explicit_index.toml") }

      let(:credentials) do
        [
          Dependabot::Credential.new(
            {
              "type" => "python_index",
              "index-url" => "https://private-pypi.example.com/simple",
              "token" => "secret_token",
              "replaces-base" => false
            }
          )
        ]
      end

      it "returns environment variables with token as password" do
        expect(explicit_index_env_vars).to include(
          "UV_INDEX_COMPANY_PYPI_PASSWORD" => "secret_token"
        )
      end
    end

    context "with no explicit indices" do
      let(:pyproject_content) { fixture("pyproject_files", "uv_non_explicit_index.toml") }

      let(:credentials) do
        [
          Dependabot::Credential.new(
            {
              "type" => "python_index",
              "index-url" => "https://private-pypi.example.com/simple",
              "token" => "token",
              "replaces-base" => false
            }
          )
        ]
      end

      it "returns empty hash" do
        expect(explicit_index_env_vars).to eq({})
      end
    end

    context "with mixed explicit and non-explicit indices" do
      let(:pyproject_content) { fixture("pyproject_files", "uv_mixed_explicit_indices.toml") }

      let(:credentials) do
        [
          Dependabot::Credential.new(
            {
              "type" => "python_index",
              "index-url" => "https://private-pypi.example.com/simple",
              "token" => "explicit_token",
              "replaces-base" => false
            }
          ),
          Dependabot::Credential.new(
            {
              "type" => "python_index",
              "index-url" => "https://fallback-pypi.example.com/simple",
              "token" => "fallback_token",
              "replaces-base" => false
            }
          )
        ]
      end

      it "returns environment variables only for explicit indices" do
        expect(explicit_index_env_vars).to include(
          "UV_INDEX_COMPANY_PYPI_PASSWORD" => "explicit_token"
        )
        expect(explicit_index_env_vars).not_to have_key("UV_INDEX_FALLBACK_PYPI_PASSWORD")
      end
    end
  end

  describe "#uv_indices" do
    subject(:uv_indices) { updater.send(:uv_indices) }

    context "with explicit index in pyproject.toml" do
      let(:pyproject_content) { fixture("pyproject_files", "uv_explicit_index.toml") }

      it "parses index configuration correctly" do
        expect(uv_indices).to include(
          "company_pypi" => { "url" => "https://private-pypi.example.com/simple", "explicit" => true }
        )
      end
    end

    context "with mixed indices in pyproject.toml" do
      let(:pyproject_content) { fixture("pyproject_files", "uv_mixed_explicit_indices.toml") }

      it "parses both explicit and non-explicit indices" do
        expect(uv_indices["company_pypi"]["explicit"]).to be true
        expect(uv_indices["fallback_pypi"]["explicit"]).to be_falsey
      end
    end

    context "with non-explicit index in pyproject.toml" do
      let(:pyproject_content) { fixture("pyproject_files", "uv_non_explicit_index.toml") }

      it "parses index without explicit flag as non-explicit" do
        expect(uv_indices["company_pypi"]["explicit"]).to be_falsey
      end
    end

    context "with no uv indices in pyproject.toml" do
      let(:pyproject_content) { fixture("pyproject_files", "uv_simple.toml") }

      it "returns empty hash" do
        expect(uv_indices).to eq({})
      end
    end
  end

  describe "#lock_options_fingerprint" do
    subject(:lock_options_fingerprint) { updater.send(:lock_options_fingerprint, options) }

    let(:options) do
      "--default-index https://another.com/simple --index https://example.com/simple"
    end

    it "replaces sensitive information in the fingerprint with placeholders" do
      expect(lock_options_fingerprint).to eq("--default-index <default_index> --index <index>")
    end
  end

  describe "#run_update_command" do
    subject(:run_update_command) { updater.send(:run_update_command) }

    let(:credentials) do
      [
        Dependabot::Credential.new(
          {
            "type" => "python_index",
            "index-url" => "https://example.com/simple",
            "token" => "token",
            "replaces-base" => false
          }
        ),
        Dependabot::Credential.new(
          {
            "type" => "python_index",
            "index-url" => "https://another.com/simple",
            "token" => "another_token",
            "replaces-base" => true
          }
        )
      ]
    end

    before do
      allow(updater).to receive(:run_command)
    end

    it "includes the expected options in the command and fingerprint" do
      expected_command = "pyenv exec uv lock --upgrade-package requests==2.23.0 " \
                         "--index https://token@example.com/simple " \
                         "--default-index https://another_token@another.com/simple"
      expected_fingerprint = "pyenv exec uv lock --upgrade-package <dependency_name> " \
                             "--index <index> " \
                             "--default-index <default_index>"

      run_update_command

      expect(updater).to have_received(:run_command).with(
        expected_command,
        fingerprint: expected_fingerprint,
        env: {}
      )
    end

    context "when dependency version is nil" do
      let(:dependency) do
        Dependabot::Dependency.new(
          name: "requests",
          version: nil,
          requirements: [{
            file: "pyproject.toml",
            requirement: ">=2.31.0",
            groups: [],
            source: nil
          }],
          previous_requirements: [{
            file: "pyproject.toml",
            requirement: ">=2.31.0",
            groups: [],
            source: nil
          }],
          previous_version: nil,
          package_manager: "uv"
        )
      end

      it "uses only the package name without version constraint" do
        expected_command = "pyenv exec uv lock --upgrade-package requests " \
                           "--index https://token@example.com/simple " \
                           "--default-index https://another_token@another.com/simple"
        expected_fingerprint = "pyenv exec uv lock --upgrade-package <dependency_name> " \
                               "--index <index> " \
                               "--default-index <default_index>"

        run_update_command

        expect(updater).to have_received(:run_command).with(
          expected_command,
          fingerprint: expected_fingerprint,
          env: {}
        )
      end
    end
  end

  describe "#replace_dep" do
    subject(:replace_dep) { updater.send(:replace_dep, dependency, content, new_req, old_req) }

    let(:content) do
      <<~TOML
        [project]
        name = "myproject"
        dependencies = [
            "fastapi>=0.115.12,<0.116",
            "uvicorn>=0.34.0,<0.35",
        ]
      TOML
    end

    let(:dependency) do
      Dependabot::Dependency.new(
        name: "fastapi",
        version: "0.115.12",
        requirements: [{
          file: "pyproject.toml",
          requirement: ">=0.115.12,<0.122",
          groups: [],
          source: nil
        }],
        previous_requirements: [{
          file: "pyproject.toml",
          requirement: ">=0.115.12,<0.116",
          groups: [],
          source: nil
        }],
        previous_version: "0.115.12",
        package_manager: "uv"
      )
    end

    let(:new_req) { { requirement: ">=0.115.12,<0.122" } }
    let(:old_req) { { requirement: ">=0.115.12,<0.116" } }

    it "replaces the requirement with the new version" do
      result = replace_dep
      expect(result).to include('"fastapi>=0.115.12,<0.122"')
      expect(result).not_to include('"fastapi>=0.115.12,<0.116"')
    end

    it "preserves other dependencies" do
      result = replace_dep
      expect(result).to include('"uvicorn>=0.34.0,<0.35"')
    end

    context "when operators are in different order" do
      let(:old_req) { { requirement: "<0.116,>=0.115.12" } }

      it "still matches and replaces correctly" do
        result = replace_dep
        expect(result).to include('"fastapi>=0.115.12,<0.122"')
        expect(result).not_to include('"fastapi>=0.115.12,<0.116"')
      end
    end

    context "when there are multiple dependencies with the same name" do
      let(:content) do
        <<~TOML
          [project]
          dependencies = [
              "fastapi>=0.100.0,<0.101",
          ]

          [dependency-groups]
          dev = [
              "fastapi>=0.115.12,<0.116",
          ]
        TOML
      end

      it "only replaces the matching version" do
        result = replace_dep
        expect(result).to include('"fastapi>=0.100.0,<0.101"')
        expect(result).to include('"fastapi>=0.115.12,<0.122"')
        expect(result).not_to include('"fastapi>=0.115.12,<0.116"')
      end
    end

    context "with exact version (==)" do
      let(:content) do
        <<~TOML
          [project]
          dependencies = [
              "fastapi==0.115.12",
          ]
        TOML
      end

      let(:new_req) { { requirement: "==0.122.0" } }
      let(:old_req) { { requirement: "==0.115.12" } }

      it "replaces the exact version" do
        result = replace_dep
        expect(result).to include('"fastapi==0.122.0"')
        expect(result).not_to include('"fastapi==0.115.12"')
      end
    end

    context "with tilde requirement (~=)" do
      let(:content) do
        <<~TOML
          [project]
          dependencies = [
              "fastapi~=0.115.0",
          ]
        TOML
      end

      let(:new_req) { { requirement: "~=0.122.0" } }
      let(:old_req) { { requirement: "~=0.115.0" } }

      it "replaces the tilde requirement" do
        result = replace_dep
        expect(result).to include('"fastapi~=0.122.0"')
        expect(result).not_to include('"fastapi~=0.115.0"')
      end
    end

    context "with single quotes" do
      let(:content) do
        <<~TOML
          [project]
          dependencies = [
              'fastapi>=0.115.12,<0.116',
          ]
        TOML
      end

      it "preserves single quotes" do
        result = replace_dep
        expect(result).to include("'fastapi>=0.115.12,<0.122'")
        expect(result).not_to include("'fastapi>=0.115.12,<0.116'")
      end
    end

    context "with package names containing dots, underscores, or hyphens (PyPI name normalization)" do
      let(:dependency) do
        Dependabot::Dependency.new(
          name: "ruamel-yaml",
          version: "0.18.6",
          requirements: [{
            file: "pyproject.toml",
            requirement: ">=0.18.6,<0.20",
            groups: [],
            source: nil
          }],
          previous_requirements: [{
            file: "pyproject.toml",
            requirement: ">=0.18.6,<0.19",
            groups: [],
            source: nil
          }],
          previous_version: "0.18.6",
          package_manager: "uv"
        )
      end

      let(:new_req) { { requirement: ">=0.18.6,<0.20" } }
      let(:old_req) { { requirement: ">=0.18.6,<0.19" } }

      context "when package name uses dots" do
        let(:content) do
          <<~TOML
            [project]
            dependencies = [
                "ruamel.yaml>=0.18.6,<0.19",
            ]
          TOML
        end

        it "replaces the requirement correctly" do
          result = replace_dep
          expect(result).to include('"ruamel.yaml>=0.18.6,<0.20"')
          expect(result).not_to include('"ruamel.yaml>=0.18.6,<0.19"')
        end
      end

      context "when dependency name uses hyphens and file uses hyphens" do
        let(:content) do
          <<~TOML
            [project]
            dependencies = [
                "ruamel-yaml>=0.18.6,<0.19",
            ]
          TOML
        end

        it "still matches and replaces the requirement correctly" do
          result = replace_dep
          expect(result).to include('"ruamel-yaml>=0.18.6,<0.20"')
          expect(result).not_to include('"ruamel-yaml>=0.18.6,<0.19"')
        end
      end

      context "when dependency name uses hyphens but file uses underscores" do
        let(:content) do
          <<~TOML
            [project]
            dependencies = [
                "ruamel_yaml>=0.18.6,<0.19",
            ]
          TOML
        end

        it "still matches and replaces the requirement correctly" do
          result = replace_dep
          expect(result).to include('"ruamel_yaml>=0.18.6,<0.20"')
          expect(result).not_to include('"ruamel_yaml>=0.18.6,<0.19"')
        end
      end

      context "with exact version (==)" do
        let(:content) do
          <<~TOML
            [project]
            dependencies = [
                "ruamel.yaml==0.18.6",
            ]
          TOML
        end

        let(:new_req) { { requirement: "==0.20.0" } }
        let(:old_req) { { requirement: "==0.18.6" } }

        it "replaces the exact version" do
          result = replace_dep
          expect(result).to include('"ruamel.yaml==0.20.0"')
          expect(result).not_to include('"ruamel.yaml==0.18.6"')
        end
      end
    end
  end

  describe "#requirements_match?" do
    subject(:requirements_match) { updater.send(:requirements_match?, req1, req2) }

    context "when requirements are identical" do
      let(:req1) { ">=0.115.12,<0.116" }
      let(:req2) { ">=0.115.12,<0.116" }

      it "returns true" do
        expect(requirements_match).to be true
      end
    end

    context "when requirements have operators in different order" do
      let(:req1) { ">=0.115.12,<0.116" }
      let(:req2) { "<0.116,>=0.115.12" }

      it "returns true" do
        expect(requirements_match).to be true
      end
    end

    context "when requirements have different whitespace" do
      let(:req1) { ">=0.115.12,<0.116" }
      let(:req2) { ">=0.115.12, <0.116" }

      it "returns true" do
        expect(requirements_match).to be true
      end
    end

    context "when requirements have three constraints in different order" do
      let(:req1) { ">=1.0.0,<2.0.0,!=1.5.0" }
      let(:req2) { "!=1.5.0,>=1.0.0,<2.0.0" }

      it "returns true" do
        expect(requirements_match).to be true
      end
    end

    context "when requirements are different" do
      let(:req1) { ">=0.115.12,<0.116" }
      let(:req2) { ">=0.115.12,<0.122" }

      it "returns false" do
        expect(requirements_match).to be false
      end
    end

    context "when one requirement is a subset of another" do
      let(:req1) { ">=0.115.12" }
      let(:req2) { ">=0.115.12,<0.116" }

      it "returns false" do
        expect(requirements_match).to be false
      end
    end
  end

  describe "#handle_uv_error" do
    subject(:handle_uv_error) { updater.send(:handle_uv_error, error) }

    context "when error contains 'No solution found when resolving dependencies'" do
      let(:error) do
        Dependabot::SharedHelpers::HelperSubprocessFailed.new(
          message: detailed_uv_error,
          error_context: {}
        )
      end

      let(:detailed_uv_error) do
        <<~ERROR
          × No solution found when resolving dependencies:
          ╰─▶ Because package-a>=1.0.0 depends on package-b>=2.0.0
              and package-c<1.0.0 depends on package-b<2.0.0,
              we can conclude that package-a>=1.0.0 and package-c<1.0.0 are incompatible.
              And because your project depends on both package-a>=1.0.0 and package-c<1.0.0,
              we can conclude that your project's requirements are unsatisfiable.
        ERROR
      end

      it "raises DependencyFileNotResolvable with the detailed error message" do
        expect { handle_uv_error }.to raise_error(Dependabot::DependencyFileNotResolvable) do |raised_error|
          expect(raised_error.message).to include("No solution found when resolving dependencies")
          expect(raised_error.message).to include("package-a>=1.0.0 depends on package-b>=2.0.0")
          expect(raised_error.message).to include("your project's requirements are unsatisfiable")
        end
      end
    end

    context "when error contains 'ResolutionImpossible'" do
      let(:error) do
        Dependabot::SharedHelpers::HelperSubprocessFailed.new(
          message: "ResolutionImpossible: Could not find a version that satisfies the requirement requests==99.99.99",
          error_context: {}
        )
      end

      it "raises DependencyFileNotResolvable with the full error message" do
        expect { handle_uv_error }.to raise_error(
          Dependabot::DependencyFileNotResolvable,
          /ResolutionImpossible.*requests==99\.99\.99/
        )
      end
    end

    context "when error contains 'Failed to build'" do
      let(:error) do
        Dependabot::SharedHelpers::HelperSubprocessFailed.new(
          message: failed_build_error,
          error_context: {}
        )
      end

      let(:failed_build_error) do
        <<~ERROR
          × Failed to build `some-package @
          │ file://dependabot_tmp_dir`
          ├─▶ The build backend returned an error
          ╰─▶ setuptools-scm was unable to detect version for dependabot_tmp_dir.
              Make sure you're either building from a fully intact git repository.
        ERROR
      end

      it "raises DependencyFileNotResolvable with the detailed error message" do
        expect { handle_uv_error }.to raise_error(Dependabot::DependencyFileNotResolvable) do |raised_error|
          expect(raised_error.message).to include("Failed to build")
          expect(raised_error.message).to include("setuptools-scm was unable to detect version")
          expect(raised_error.message).to include("Make sure you're either building from a fully intact git repository")
        end
      end
    end
  end
end
