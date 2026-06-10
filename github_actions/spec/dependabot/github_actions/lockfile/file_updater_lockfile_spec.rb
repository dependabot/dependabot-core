# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency"
require "dependabot/dependency_file"
require "dependabot/github_actions/file_updater"
require "dependabot/github_actions/version"

# Focused coverage for the actions.lock relock path in the FileUpdater. Stubs the
# Engine.build boundary so these examples stay hermetic (no binary/network). Kept
# beside the other lockfile specs rather than at the canonical file_updater_spec.rb path.
RSpec.describe Dependabot::GithubActions::FileUpdater do # rubocop:disable RSpec/SpecFilePathFormat
  subject(:updated_files) { updater.updated_dependency_files }

  let(:dependency) do
    Dependabot::Dependency.new(
      name: "actions/setup-node",
      version: "5273d0df9c603edc4284ac8402cf650b4f1f6686",
      previous_version: nil,
      package_manager: "github_actions",
      requirements: [{
        requirement: nil, groups: [], file: workflow_name,
        source: { type: "git", url: "https://github.com/actions/setup-node", ref: "v1.1.0", branch: nil },
        metadata: { declaration_string: "actions/setup-node@master" }
      }],
      previous_requirements: [{
        requirement: nil, groups: [], file: workflow_name,
        source: { type: "git", url: "https://github.com/actions/setup-node", ref: "master", branch: nil },
        metadata: { declaration_string: "actions/setup-node@master" }
      }]
    )
  end
  let(:workflow_name) { ".github/workflows/workflow.yml" }
  let(:workflow_file) do
    Dependabot::DependencyFile.new(content: fixture("workflow_files", "workflow.yml"), name: workflow_name)
  end
  let(:lock_file) do
    Dependabot::DependencyFile.new(
      content: fixture("lockfiles", "actions.lock"),
      name: ".github/workflows/actions.lock"
    )
  end
  let(:credentials) do
    [{ "type" => "git_source", "host" => "github.com", "username" => "x-access-token", "password" => "token" }]
  end
  let(:updater) do
    described_class.new(dependency_files: files, dependencies: [dependency], credentials: credentials)
  end

  # CliEngine is the only engine; these examples stay hermetic by stubbing the
  # Engine.build boundary with a canned relock result. The relock CORRECTNESS lives
  # in cli_engine_spec; here we assert the FileUpdater wiring (engine output emitted
  # as a normal updated file). The malformed/unsupported/legacy contexts below never
  # reach the engine — they raise or take the regex path first — so the stub is inert.
  let(:relocked_lock_content) do
    <<~LOCK
      version: v0.0.1
      workflows:
        ".github/workflows/workflow.yml":
          - "actions/setup-node@v1.1.0:sha1-5273d0df9c603edc4284ac8402cf650b4f1f6686"
      dependencies:
        "actions/setup-node@v1.1.0:sha1-5273d0df9c603edc4284ac8402cf650b4f1f6686":
          branch: master
          commit: sha1-5273d0df9c603edc4284ac8402cf650b4f1f6686
          owner_id: 44036562
          repo_id: 167274481
          tag: v1.1.0
    LOCK
  end
  let(:fake_engine) do
    instance_double(
      Dependabot::GithubActions::Lockfile::Engine,
      relock: Dependabot::GithubActions::Lockfile::RelockResult.new(
        lockfile_content: relocked_lock_content
      )
    )
  end

  before do
    allow(Dependabot::GithubActions::Lockfile::Engine).to receive(:build).and_return(fake_engine)
  end

  def updated(name)
    updated_files.find { |f| f.name == name }
  end

  context "when the workflow is onboarded to the lockfile" do
    let(:files) { [workflow_file, lock_file] }

    it "rewrites the workflow file" do
      expect(updated(workflow_name).content).to include("actions/setup-node@v1.1.0")
    end

    it "emits a regenerated actions.lock" do
      lock = updated(".github/workflows/actions.lock")
      expect(lock).not_to be_nil
      expect(lock.content).to include("actions/setup-node@v1.1.0:sha1-5273d0df9c603edc4284ac8402cf650b4f1f6686")
    end

    it "does not return the lockfile unchanged" do
      expect(updated(".github/workflows/actions.lock").content).not_to eq(lock_file.content)
    end

    # The platform diffs updated_dependency_files into a PR commit, but first drops
    # support files (dependency_change_builder.rb) and turns each file's `operation`
    # into the git file op. The lock must ride along as a normal `update`, or it
    # silently vanishes from the PR.
    it "emits the lockfile as a normal updated file (not a support file)" do
      lock = updated(".github/workflows/actions.lock")
      expect(lock.support_file?).to be(false)
    end

    it "emits the lockfile with the update operation" do
      lock = updated(".github/workflows/actions.lock")
      expect(lock.operation).to eq(Dependabot::DependencyFile::Operation::UPDATE)
      expect(lock.deleted?).to be(false)
    end
  end

  context "when there is no lockfile (regression: legacy regex path)" do
    let(:files) { [workflow_file] }

    it "rewrites the workflow file exactly as before" do
      expect(updated(workflow_name).content).to include("actions/setup-node@v1.1.0")
    end

    it "emits only the workflow file and no lockfile" do
      expect(updated_files.map(&:name)).to eq([workflow_name])
    end
  end

  context "when a lockfile exists but does not cover the changed workflow" do
    let(:workflow_name) { ".github/workflows/legacy.yml" }
    let(:files) { [workflow_file, lock_file] }

    it "uses the legacy path and does not regenerate the lock" do
      expect(updated_files.map(&:name)).to eq([workflow_name])
    end
  end

  context "when the lockfile covers the changed workflow but a dependency entry is malformed" do
    let(:lock_file) do
      Dependabot::DependencyFile.new(
        content: fixture("lockfiles", "actions.lock").sub("    owner_id: 44036562\n", ""),
        name: ".github/workflows/actions.lock"
      )
    end
    let(:files) { [workflow_file, lock_file] }

    it "raises DependencyFileNotParseable instead of silently relocking to a no-op" do
      expect { updated_files }
        .to raise_error(Dependabot::DependencyFileNotParseable, /missing required field.*owner_id/)
    end
  end

  context "when a malformed lockfile covers only an untouched workflow" do
    let(:workflow_name) { ".github/workflows/legacy.yml" }
    let(:lock_file) do
      Dependabot::DependencyFile.new(
        content: fixture("lockfiles", "actions.lock").sub("    owner_id: 44036562\n", ""),
        name: ".github/workflows/actions.lock"
      )
    end
    let(:files) { [workflow_file, lock_file] }

    it "does not raise and uses the legacy path" do
      expect(updated_files.map(&:name)).to eq([workflow_name])
    end
  end

  context "when the lockfile schema major is unsupported and covers the changed workflow" do
    let(:lock_file) do
      Dependabot::DependencyFile.new(
        content: fixture("lockfiles", "actions.lock").sub("version: v0.0.1", "version: v9.0.0"),
        name: ".github/workflows/actions.lock"
      )
    end
    let(:files) { [workflow_file, lock_file] }

    it "raises UnsupportedLockfileVersion" do
      expect { updated_files }
        .to raise_error(Dependabot::GithubActions::Lockfile::UnsupportedLockfileVersion)
    end
  end

  context "when an unsupported lockfile covers only an untouched workflow" do
    let(:workflow_name) { ".github/workflows/legacy.yml" }
    let(:lock_file) do
      Dependabot::DependencyFile.new(
        content: fixture("lockfiles", "actions.lock").sub("version: v0.0.1", "version: v9.0.0"),
        name: ".github/workflows/actions.lock"
      )
    end
    let(:files) { [workflow_file, lock_file] }

    it "does not raise and uses the legacy path" do
      expect(updated_files.map(&:name)).to eq([workflow_name])
    end
  end
end
