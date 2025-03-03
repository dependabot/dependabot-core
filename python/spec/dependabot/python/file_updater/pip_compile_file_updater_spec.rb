# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency"
require "dependabot/dependency_file"
require "dependabot/python/file_updater/pip_compile_file_updater"
require "dependabot/shared_helpers"

RSpec.describe Dependabot::Python::FileUpdater::PipCompileFileUpdater do
  let(:updater) do
    described_class.new(
      dependency_files: dependency_files,
      dependencies: [dependency],
      credentials: credentials
    )
  end
  let(:dependency_files) { [manifest_file, generated_file] }
  let(:manifest_file) do
    Dependabot::DependencyFile.new(
      name: "requirements/test.in",
      content: fixture("pip_compile_files", manifest_fixture_name)
    )
  end
  let(:generated_file) do
    Dependabot::DependencyFile.new(
      name: "requirements/test.txt",
      content: fixture("requirements", generated_fixture_name)
    )
  end
  let(:manifest_fixture_name) { "unpinned.in" }
  let(:generated_fixture_name) { "pip_compile_unpinned.txt" }
  let(:dependency) do
    Dependabot::Dependency.new(
      name: dependency_name,
      version: dependency_version,
      previous_version: dependency_previous_version,
      requirements: dependency_requirements,
      previous_requirements: dependency_previous_requirements,
      package_manager: "pip"
    )
  end
  let(:dependency_name) { "attrs" }
  let(:dependency_version) { "18.1.0" }
  let(:dependency_previous_version) { "17.3.0" }
  let(:dependency_requirements) do
    [{
      file: "requirements/test.in",
      requirement: nil,
      groups: [],
      source: nil
    }]
  end
  let(:dependency_previous_requirements) do
    [{
      file: "requirements/test.in",
      requirement: nil,
      groups: [],
      source: nil
    }]
  end
  let(:credentials) do
    [Dependabot::Credential.new({
      "type" => "git_source",
      "host" => "github.com",
      "username" => "x-access-token",
      "password" => "token"
    })]
  end
  let(:tmp_path) { Dependabot::Utils::BUMP_TMP_DIR_PATH }

  before { FileUtils.mkdir_p(tmp_path) }

  describe "#updated_dependency_files" do
    subject(:updated_files) { updater.updated_dependency_files }

    it "updates the requirements.txt" do
      expect(updated_files.count).to eq(1)
      expect(updated_files.first.content).to include("attrs==18.1.0")
      expect(updated_files.first.content)
        .to include("pbr==4.0.2\n    # via mock")
      expect(updated_files.first.content).to include("# This file is autogen")
      expect(updated_files.first.content).not_to include("--hash=sha")
    end

    context "with a mismatch in filename" do
      let(:generated_fixture_name) { "pip_compile_unpinned_renamed.txt" }
      let(:generated_file) do
        Dependabot::DependencyFile.new(
          name: "requirements/test-funky.txt",
          content: fixture("requirements", generated_fixture_name)
        )
      end

      it "updates the requirements.txt" do
        expect(updated_files.count).to eq(1)
        expect(updated_files.first.content).to include("attrs==18.1.0")
        expect(updated_files.first.content)
          .to include("pbr==4.0.2\n    # via mock")
        expect(updated_files.first.content).to include("# This file is autogen")
        expect(updated_files.first.content).not_to include("--hash=sha")
      end
    end

    context "with a custom header" do
      let(:generated_fixture_name) { "pip_compile_custom_header.txt" }

      it "preserves the header" do
        expect(updated_files.count).to eq(1)
        expect(updated_files.first.content).to include("attrs==18.1.0")
        expect(updated_files.first.content).to include("make upgrade")
      end
    end

    context "with a no-binary flag" do
      let(:manifest_fixture_name) { "no_binary.in" }
      let(:generated_fixture_name) { "pip_compile_no_binary.txt" }
      let(:dependency_name) { "psycopg2" }
      let(:dependency_version) { "2.7.6" }
      let(:dependency_previous_version) { "2.7.4" }

      it "updates the requirements.txt correctly" do
        expect(updated_files.count).to eq(1)
        expect(updated_files.first.content).to include("psycopg2==2.7.6")
        expect(updated_files.first.content).to include("--no-binary psycopg2")
        expect(updated_files.first.content)
          .not_to include("--no-binary psycopg2==")
      end
    end

    context "with hashes" do
      let(:generated_fixture_name) { "pip_compile_hashes.txt" }

      it "updates the requirements.txt, keeping the hashes" do
        expect(updated_files.count).to eq(1)
        expect(updated_files.first.content).to include("attrs==18.1.0")
        expect(updated_files.first.content).to include("4b90b09eeeb9b88c35bc64")
        expect(updated_files.first.content)
          .not_to include("# This file is autogen")
      end

      context "when needing an augmented hashin" do
        let(:manifest_fixture_name) { "extra_hashes.in" }
        let(:generated_fixture_name) { "pip_compile_extra_hashes.txt" }
        let(:dependency_name) { "pyasn1-modules" }
        let(:dependency_version) { "0.1.5" }
        let(:dependency_previous_version) { "0.1.4" }

        it "updates the requirements.txt, keeping all the hashes" do
          expect(updated_files.count).to eq(1)
          expect(updated_files.first.content)
            .to include("# This file is autogen")
          expect(updated_files.first.content)
            .to include("pyasn1-modules==0.1.5 \\\n    --hash=sha256:01")
          expect(updated_files.first.content)
            .to include("--hash=sha256:b437be576bdf440fc0e930")
          expect(updated_files.first.content)
            .to include("pyasn1==0.3.7 \\\n    --hash=sha256:16")
          expect(updated_files.first.content)
            .to include("--hash=sha256:bb6f5d5507621e0298794b")
          expect(updated_files.first.content)
            .to include("# via pyasn1-modules")
          expect(updated_files.first.content).not_to include("WARNING")
        end
      end
    end

    context "with another dependency with an unmet marker" do
      let(:manifest_fixture_name) { "unmet_marker.in" }
      let(:generated_fixture_name) { "pip_compile_unmet_marker.txt" }

      it "updates the requirements.txt, keeping the unmet dep out of it" do
        expect(updated_files.count).to eq(1)
        expect(updated_files.first.content).to include("attrs==18.1.0")
        expect(updated_files.first.content).not_to include("flaky")
      end
    end

    context "with an unsafe dependency" do
      let(:manifest_fixture_name) { "unsafe.in" }
      let(:dependency_name) { "flake8" }
      let(:dependency_version) { "3.6.0" }
      let(:dependency_previous_version) { "3.5.0" }

      context "when not including in the lockfile" do
        let(:generated_fixture_name) { "pip_compile_safe.txt" }

        it "does not include the unsafe dependency" do
          expect(updated_files.count).to eq(1)
          expect(updated_files.first.content).to include("flake8==3.6.0")
          expect(updated_files.first.content).not_to include("setuptools")
          expect(updated_files.first.content).to end_with("via flake8\n")
        end
      end

      context "when including in the lockfile" do
        let(:generated_fixture_name) { "pip_compile_unsafe.txt" }

        it "includes the unsafe dependency" do
          expect(updated_files.count).to eq(1)
          expect(updated_files.first.content).to include("flake8==3.6.0")
          expect(updated_files.first.content).to include("setuptools")
        end
      end
    end

    context "with an import of the setup.py" do
      let(:dependency_files) do
        [manifest_file, generated_file, setup_file, pyproject]
      end
      let(:setup_file) do
        Dependabot::DependencyFile.new(
          name: "setup.py",
          content: fixture("setup_files", setup_fixture_name)
        )
      end
      let(:pyproject) do
        Dependabot::DependencyFile.new(
          name: "pyproject.toml",
          content: fixture("pyproject_files", "black_configuration.toml")
        )
      end
      let(:manifest_fixture_name) { "imports_setup.in" }
      let(:generated_fixture_name) { "pip_compile_imports_setup.txt" }
      let(:setup_fixture_name) { "small.py" }

      it "updates the requirements.txt", :slow do
        expect(updated_files.count).to eq(1)
        expect(updated_files.first.content).to include("attrs==18.1.0")
        expect(updated_files.first.content)
          .to include("-e file:///Users/greysteil/code/python-test")
        expect(updated_files.first.content).not_to include("tmp/dependabot")
        expect(updated_files.first.content)
          .to include("pbr==4.0.2\n    # via mock")
        expect(updated_files.first.content).to include("# This file is autogen")
        expect(updated_files.first.content).not_to include("--hash=sha")
      end

      context "when needing sanitization", :slow do
        let(:setup_fixture_name) { "small_needs_sanitizing.py" }

        it "updates the requirements.txt" do
          expect(updated_files.count).to eq(1)
          expect(updated_files.first.content).to include("attrs==18.1.0")
        end
      end
    end

    context "with editable dependencies (that are misordered in the .txt)" do
      let(:manifest_fixture_name) { "editable.in" }
      let(:generated_fixture_name) { "pip_compile_editable.txt" }

      it "updates the requirements.txt" do
        expect(updated_files.count).to eq(1)
        expect(updated_files.first.content).to include("attrs==18.1.0")
        expect(updated_files.first.content)
          .to include("-e git+https://github.com/testing-cabal/mock.git@2.0.0")
        expect(updated_files.first.content)
          .to include("-e git+https://github.com/box/flaky.git@v3.5.3#egg=flaky")
      end
    end

    context "with a subdependency" do
      let(:dependency_name) { "pbr" }
      let(:dependency_version) { "4.2.0" }
      let(:dependency_previous_version) { "4.0.2" }
      let(:dependency_requirements) { [] }
      let(:dependency_previous_requirements) { [] }

      it "updates the requirements.txt" do
        expect(updated_files.count).to eq(1)
        expect(updated_files.first.content)
          .to include("pbr==4.2.0\n    # via mock")
      end

      context "with an uncompiled requirement file, too" do
        let(:dependency_files) do
          [manifest_file, generated_file, requirement_file]
        end
        let(:requirement_file) do
          Dependabot::DependencyFile.new(
            name: "requirements.txt",
            content: fixture("requirements", "pbr.txt")
          )
        end
        let(:dependency_requirements) do
          [{
            file: "requirements.txt",
            requirement: "==4.2.0",
            groups: [],
            source: nil
          }]
        end
        let(:dependency_previous_requirements) do
          [{
            file: "requirements.txt",
            requirement: "==4.0.2",
            groups: [],
            source: nil
          }]
        end

        it "updates the requirements.txt" do
          expect(updated_files.count).to eq(2)
          expect(updated_files.first.content)
            .to include("pbr==4.2.0\n    # via mock")
          expect(updated_files.last.content).to include("pbr==4.2.0")
        end
      end
    end

    context "when targeting a non-latest version" do
      let(:dependency_version) { "17.4.0" }

      it "updates the requirements.txt" do
        expect(updated_files.count).to eq(1)
        expect(updated_files.first.content).to include("attrs==17.4.0")
        expect(updated_files.first.content)
          .to include("pbr==4.0.2\n    # via mock")
        expect(updated_files.first.content).to include("# This file is autogen")
        expect(updated_files.first.content).not_to include("--hash=sha")
      end
    end

    context "when the requirement.in file needs to be updated" do
      let(:manifest_fixture_name) { "bounded.in" }
      let(:generated_fixture_name) { "pip_compile_bounded.txt" }

      let(:dependency_requirements) do
        [{
          file: "requirements/test.in",
          requirement: "<=18.1.0",
          groups: [],
          source: nil
        }]
      end
      let(:dependency_previous_requirements) do
        [{
          file: "requirements/test.in",
          requirement: "<=17.4.0",
          groups: [],
          source: nil
        }]
      end

      it "updates the requirements.txt and the requirements.in" do
        expect(updated_files.count).to eq(2)
        expect(updated_files.first.content).to include("Attrs<=18.1.0")
        expect(updated_files.last.content).to include("attrs==18.1.0")
        expect(updated_files.last.content).not_to include("# via mock")
      end

      context "with an additional requirements.txt" do
        let(:dependency_files) { [manifest_file, generated_file, other_txt] }
        let(:other_txt) do
          Dependabot::DependencyFile.new(
            name: "requirements.txt",
            content:
              fixture("requirements", "pip_compile_unpinned.txt")
          )
        end

        let(:dependency_requirements) do
          [{
            file: "requirements/test.in",
            requirement: "<=18.1.0",
            groups: [],
            source: nil
          }, {
            file: "requirements.txt",
            requirement: "==18.1.0",
            groups: [],
            source: nil
          }]
        end
        let(:dependency_previous_requirements) do
          [{
            file: "requirements/test.in",
            requirement: "<=17.4.0",
            groups: [],
            source: nil
          }, {
            file: "requirements.txt",
            requirement: "==17.3.0",
            groups: [],
            source: nil
          }]
        end

        it "updates the other requirements.txt, too" do
          expect(updated_files.count).to eq(3)
          expect(updated_files.first.content).to include("Attrs<=18.1.0")
          expect(updated_files[1].content).to include("attrs==18.1.0")
          expect(updated_files.last.content).to include("attrs==18.1.0")
        end
      end

      context "with multiple requirement.in files" do
        let(:dependency_files) do
          [
            manifest_file, manifest_file2, manifest_file3, manifest_file4,
            generated_file, generated_file2, generated_file3, generated_file4
          ]
        end

        let(:manifest_file2) do
          Dependabot::DependencyFile.new(
            name: "requirements/dev.in",
            content:
              fixture("pip_compile_files", manifest_fixture_name)
          )
        end
        let(:generated_file2) do
          Dependabot::DependencyFile.new(
            name: "requirements/dev.txt",
            content: fixture("requirements", generated_fixture_name)
          )
        end

        let(:manifest_file3) do
          Dependabot::DependencyFile.new(
            name: "requirements/mirror2.in",
            content:
              fixture("pip_compile_files", "imports_mirror.in")
          )
        end
        let(:generated_file3) do
          Dependabot::DependencyFile.new(
            name: "requirements/mirror2.txt",
            content: fixture("requirements", generated_fixture_name)
          )
        end

        let(:manifest_file4) do
          Dependabot::DependencyFile.new(
            name: "requirements/mirror.in",
            content:
              fixture("pip_compile_files", "imports_dev.in")
          )
        end
        let(:generated_file4) do
          Dependabot::DependencyFile.new(
            name: "requirements/mirror.txt",
            content: fixture("requirements", generated_fixture_name)
          )
        end

        let(:dependency_requirements) do
          [{
            file: "requirements/test.in",
            requirement: "<=18.1.0",
            groups: [],
            source: nil
          }, {
            file: "requirements/dev.in",
            requirement: "<=18.1.0",
            groups: [],
            source: nil
          }]
        end
        let(:dependency_previous_requirements) do
          [{
            file: "requirements/test.in",
            requirement: "<=17.4.0",
            groups: [],
            source: nil
          }, {
            file: "requirements/dev.in",
            requirement: "<=17.4.0",
            groups: [],
            source: nil
          }]
        end

        it "updates the other manifest file, too" do
          expect(updated_files.count).to eq(6)
          expect(updated_files[0].name).to eq("requirements/test.in")
          expect(updated_files[1].name).to eq("requirements/dev.in")
          expect(updated_files[2].name).to eq("requirements/test.txt")
          expect(updated_files[3].name).to eq("requirements/dev.txt")
          expect(updated_files[4].name).to eq("requirements/mirror2.txt")
          expect(updated_files[5].name).to eq("requirements/mirror.txt")
          expect(updated_files[0].content).to include("Attrs<=18.1.0")
          expect(updated_files[1].content).to include("Attrs<=18.1.0")
          expect(updated_files[2].content).to include("attrs==18.1.0")
          expect(updated_files[3].content).to include("attrs==18.1.0")
          expect(updated_files[4].content).to include("attrs==18.1.0")
          expect(updated_files[5].content).to include("attrs==18.1.0")
        end
      end
    end

    context "with incompatible versions" do
      let(:manifest_fixture_name) { "incompatible_versions.in" }
      let(:generated_fixture_name) { "incompatible_versions.txt" }
      let(:dependency_name) { "pyyaml" }
      let(:dependency_version) { "6.0.1" }
      let(:dependency_previous_version) { "5.3.1" }
      let(:dependency_requirements) { [] }
      let(:dependency_previous_requirements) { [] }

      it "raises an error indicating the dependencies are not resolvable", :slow do
        expect { updated_files }.to raise_error(Dependabot::DependencyFileNotResolvable) do |err|
          expect(err.message).to include(
            "There are incompatible versions in the resolved dependencies:\n  pyyaml==6.0.1"
          )
        end
      end
    end

    context "with stripped extras" do
      let(:manifest_fixture_name) { "strip_extras.in" }
      let(:generated_fixture_name) { "pip_compile_strip_extras.txt" }
      let(:dependency_name) { "cachecontrol" }
      let(:dependency_version) { "0.12.10" }
      let(:dependency_previous_version) { "0.12.9" }

      it "doesn't add an extras annotation on cachecontrol" do
        expect(updated_files.count).to eq(1)
        expect(updated_files.first.content).to include("--strip-extras")
        expect(updated_files.first.content).to include("cachecontrol==0.12.10")
        expect(updated_files.first.content)
          .not_to include("cachecontrol[filecache]==")
      end
    end

    context "with resolver backtracking header" do
      let(:manifest_fixture_name) { "celery_extra_sqs.in" }
      let(:generated_fixture_name) { "pip_compile_resolver_backtracking.txt" }
      let(:dependency_name) { "celery" }
      let(:dependency_version) { "5.2.7" }
      let(:dependency_previous_version) { "5.2.6" }

      it "adds pycurl as dependency" do
        expect(updated_files.count).to eq(1)
        expect(updated_files.first.content).to include("--resolver=backtracking")
        expect(updated_files.first.content).to include("pycurl")
      end
    end

    context "with resolver legacy header" do
      let(:manifest_fixture_name) { "celery_extra_sqs.in" }
      let(:generated_fixture_name) { "pip_compile_resolver_legacy.txt" }
      let(:dependency_name) { "celery" }
      let(:dependency_version) { "5.2.7" }
      let(:dependency_previous_version) { "5.2.6" }

      it "do not include pycurl" do
        expect(updated_files.count).to eq(1)
        expect(updated_files.first.content).to include("--resolver=legacy")
        expect(updated_files.first.content).not_to include("pycurl")
      end
    end
  end

  describe "#package_hashes_for" do
    let(:name) { "package_name" }
    let(:version) { "1.0.0" }
    let(:algorithm) { "sha256" }

    context "when index_urls is not set" do
      let(:updater) do
        described_class.new(
          dependencies: [],
          dependency_files: [],
          credentials: []
        )
      end

      before do
        allow(Dependabot::SharedHelpers).to receive(:run_helper_subprocess).and_return([{ "hash" => "123abc" }])
      end

      it "returns hash" do
        result = updater.send(:package_hashes_for, name: name, version: version, algorithm: algorithm)
        expect(result).to eq(["--hash=sha256:123abc"])
      end
    end

    context "when multiple index_urls are set" do
      let(:updater) do
        described_class.new(
          dependencies: [],
          dependency_files: [],
          credentials: [],
          index_urls: [nil, "http://example.com"]
        )
      end

      before do
        allow(Dependabot::SharedHelpers).to receive(:run_helper_subprocess)
          .and_return([{ "hash" => "123abc" }], [{ "hash" => "312cba" }])
      end

      it "returns returns two hashes" do
        result = updater.send(:package_hashes_for, name: name, version: version, algorithm: algorithm)
        expect(result).to eq(%w(--hash=sha256:123abc --hash=sha256:312cba))
      end
    end

    context "when multiple index_urls are set but package does not exist in PyPI" do
      let(:updater) do
        described_class.new(
          dependencies: [],
          dependency_files: [],
          credentials: [],
          index_urls: [nil, "http://example.com"]
        )
      end

      before do
        allow(Dependabot::SharedHelpers).to receive(:run_helper_subprocess).with({
          args: %w(package_name 1.0.0 sha256),
          command: "pyenv exec python3 /opt/python/run.py",
          function: "get_dependency_hash"
        }).and_raise(
          Dependabot::SharedHelpers::HelperSubprocessFailed.new(
            message: "Error message", error_context: {}, error_class: "PackageNotFoundError"
          )
        )

        allow(Dependabot::SharedHelpers).to receive(:run_helper_subprocess)
          .with({
            args: %w(package_name 1.0.0 sha256 http://example.com),
            command: "pyenv exec python3 /opt/python/run.py",
            function: "get_dependency_hash"
          }).and_return([{ "hash" => "123abc" }])
      end

      it "returns returns two hashes" do
        result = updater.send(:package_hashes_for, name: name, version: version, algorithm: algorithm)
        expect(result).to eq(["--hash=sha256:123abc"])
      end
    end
  end
end
