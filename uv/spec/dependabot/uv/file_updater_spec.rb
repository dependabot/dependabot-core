# typed: false
# frozen_string_literal: true

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

    context "when only plain requirements files are present" do
      let(:dependency_files) { [requirements] }

      it "delegates to RequirementFileUpdater" do
        expect(described_class::RequirementFileUpdater)
          .to receive(:new).and_call_original
        expect { updated_files }.not_to(change { Dir.entries(tmp_path) })
        expect(updated_files).to all(be_a(Dependabot::DependencyFile))
      end
    end

    context "when both updaters return pyproject.toml" do
      let(:dependency_files) { [requirements] }

      it "deduplicates files by name" do
        req_pyproject = Data.define(:name).new("pyproject.toml")
        lock_pyproject = Data.define(:name).new("pyproject.toml")
        lockfile = Data.define(:name).new("uv.lock")

        req_updater = instance_double(described_class::RequirementFileUpdater)
        allow(described_class::RequirementFileUpdater).to receive(:new)
          .and_return(req_updater)
        allow(req_updater)
          .to receive(:updated_dependency_files)
          .and_return([req_pyproject])

        lock_updater = instance_double(described_class::LockFileUpdater)
        allow(described_class::LockFileUpdater).to receive(:new)
          .and_return(lock_updater)
        allow(lock_updater)
          .to receive(:updated_dependency_files)
          .and_return([lock_pyproject, lockfile])

        result = updater.updated_dependency_files
        expect(result.map(&:name)).to eq(%w(pyproject.toml uv.lock))
      end
    end

    describe "#index_urls" do
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
          expect(instance.send(:index_urls)).to eq(["authed_url"])
        end
      end

      context "when credentials do not replace base" do
        it "returns nil and authed urls for all credentials" do
          expect(instance.send(:index_urls)).to eq([nil, "authed_url"])
        end
      end
    end
  end
end
