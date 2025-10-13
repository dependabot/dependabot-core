# typed: false
# frozen_string_literal: true

require "ostruct"

require "spec_helper"
require "dependabot/dependency"
require "dependabot/dependency_file"
require "dependabot/uv/file_updater"
require "dependabot/shared_helpers"
require_common_spec "file_updaters/shared_examples_for_file_updaters"

RSpec.describe Dependabot::Uv::FileUpdater do
  let(:tmp_path) { Dependabot::Utils::BUMP_TMP_DIR_PATH }
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
  let(:dependency) do
    Dependabot::Dependency.new(
      name: "psycopg2",
      version: "2.8.1",
      requirements: [{
        file: "requirements.txt",
        requirement: "==2.8.1",
        groups: [],
        source: nil
      }],
      previous_requirements: [{
        file: "requirements.txt",
        requirement: "==2.6.1",
        groups: [],
        source: nil
      }],
      package_manager: "uv"
    )
  end
  let(:requirements_fixture_name) { "version_specified.txt" }
  let(:requirements) do
    Dependabot::DependencyFile.new(
      content: fixture("requirements", requirements_fixture_name),
      name: "requirements.txt"
    )
  end
  let(:dependency_files) { [requirements] }
  let(:updater) do
    described_class.new(
      dependency_files: dependency_files,
      dependencies: [dependency],
      credentials: credentials
    )
  end

  before { FileUtils.mkdir_p(tmp_path) }

  it_behaves_like "a dependency file updater"

  describe "#updated_dependency_files" do
    subject(:updated_files) { updater.updated_dependency_files }

    context "with a pip-compile file" do
      let(:dependency_files) { [manifest_file, generated_file] }
      let(:manifest_file) do
        Dependabot::DependencyFile.new(
          name: "requirements/test.in",
          content: fixture("pip_compile_files", "unpinned.in")
        )
      end
      let(:generated_file) do
        Dependabot::DependencyFile.new(
          name: "requirements/test.txt",
          content: fixture("requirements", "pip_compile_unpinned.txt")
        )
      end
      let(:dependency) do
        Dependabot::Dependency.new(
          name: "psycopg2",
          version: "2.8.1",
          requirements: [{
            file: "requirements/test.in",
            requirement: "==2.8.1",
            groups: [],
            source: nil
          }],
          previous_requirements: [{
            file: "requirements/test.in",
            requirement: "==2.7.1",
            groups: [],
            source: nil
          }],
          package_manager: "uv"
        )
      end

      it "delegates to CompileFileUpdater" do
        dummy_updater =
          instance_double(described_class::CompileFileUpdater)
        allow(described_class::CompileFileUpdater).to receive(:new)
          .and_return(dummy_updater)
        allow(dummy_updater)
          .to receive(:updated_dependency_files)
          .and_return([OpenStruct.new(name: "updated files")])
        expect(updater.updated_dependency_files)
          .to eq([OpenStruct.new(name: "updated files")])
      end

      context "when a requirements.txt that specifies a subdependency" do
        let(:dependency_files) { [manifest_file, generated_file, requirements] }
        let(:manifest_fixture_name) { "requests.in" }
        let(:generated_fixture_name) { "pip_compile_requests.txt" }
        let(:requirements_fixture_name) { "urllib.txt" }
        let(:pypi_url) { "https://pypi.org/simple/urllib/" }

        let(:dependency_name) { "urllib" }
        let(:dependency_version) { "1.22" }
        let(:dependency_requirements) do
          [{
            file: "requirements.txt",
            requirement: nil,
            groups: [],
            source: nil
          }]
        end

        it "delegates to CompileFileUpdater" do
          dummy_updater =
            instance_double(described_class::CompileFileUpdater)
          allow(described_class::CompileFileUpdater).to receive(:new)
            .and_return(dummy_updater)
          allow(dummy_updater)
            .to receive(:updated_dependency_files)
            .and_return([OpenStruct.new(name: "updated files")])
          expect(updater.updated_dependency_files)
            .to eq([OpenStruct.new(name: "updated files")])
        end
      end
    end

    describe "with no Pipfile or pip-compile files" do
      let(:dependency_files) { [requirements] }

      it "delegates to RequirementFileUpdater" do
        expect(described_class::RequirementFileUpdater)
          .to receive(:new).and_call_original
        expect { updated_files }.not_to(change { Dir.entries(tmp_path) })
        expect(updated_files).to all(be_a(Dependabot::DependencyFile))
      end
    end

    describe "#pip_compile_index_urls" do
      let(:instance) do
        described_class.new(
          dependencies: [],
          dependency_files: [],
          credentials: credentials
        )
      end

      let(:credentials) { [instance_double(Dependabot::Credential, replaces_base?: replaces_base)] }
      let(:replaces_base) { false }

      before do
        allow_any_instance_of(described_class).to receive(:check_required_files).and_return(true) # rubocop:disable RSpec/AnyInstance
        allow(Dependabot::Uv::AuthedUrlBuilder).to receive(:authed_url).and_return("authed_url")
      end

      context "when credentials replace base" do
        let(:replaces_base) { true }

        it "returns authed urls for these credentials" do
          expect(instance.send(:pip_compile_index_urls)).to eq(["authed_url"])
        end
      end

      context "when credentials do not replace base" do
        it "returns nil and authed urls for all credentials" do
          expect(instance.send(:pip_compile_index_urls)).to eq([nil, "authed_url"])
        end
      end
    end
  end
end
