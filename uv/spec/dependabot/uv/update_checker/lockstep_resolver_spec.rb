# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency"
require "dependabot/dependency_file"
require "dependabot/requirements_update_strategy"
require "dependabot/uv/update_checker/lockstep_resolver"

RSpec.describe Dependabot::Uv::UpdateChecker::LockstepResolver do
  let(:resolver) do
    described_class.new(
      dependency: api,
      dependency_files: dependency_files,
      credentials: [],
      repo_contents_path: nil,
      requirements_update_strategy: Dependabot::RequirementsUpdateStrategy::BumpVersions,
      update_cooldown: nil
    )
  end

  let(:pyproject) do
    Dependabot::DependencyFile.new(name: "pyproject.toml", content: fixture("pyproject_files", "lockstep_pinned.toml"))
  end
  let(:lockfile) do
    Dependabot::DependencyFile.new(name: "uv.lock", content: fixture("uv_locks", "lockstep_pinned.lock"))
  end
  let(:dependency_files) { [pyproject, lockfile] }

  let(:api) { pinned("opentelemetry-api", "1.25.0") }
  let(:sdk) { pinned("opentelemetry-sdk", "1.25.0") }
  let(:top_level) { [api, sdk] }
  let(:target) { Dependabot::Uv::Version.new("1.26.0") }

  let(:lock_updater) { instance_double(Dependabot::Uv::FileUpdater::LockFileUpdater) }
  let(:resolved_lockfile) do
    Dependabot::DependencyFile.new(name: "uv.lock", content: bumped_lock(%w(opentelemetry-api opentelemetry-sdk)))
  end
  let(:conflict) do
    Dependabot::UpdateNotPossible.new(%w(opentelemetry-sdk opentelemetry-api))
  end

  def pinned(name, version)
    Dependabot::Dependency.new(
      name: name,
      version: version,
      requirements: [{ file: "pyproject.toml", requirement: "==#{version}", groups: [], source: nil }],
      package_manager: "uv"
    )
  end

  def bumped_lock(names)
    names.reduce(fixture("uv_locks", "lockstep_pinned.lock")) do |content, name|
      content.gsub("name = \"#{name}\"\nversion = \"1.25.0\"", "name = \"#{name}\"\nversion = \"1.26.0\"")
    end
  end

  before do
    allow(Dependabot::Uv::FileParser).to receive(:new)
      .and_return(instance_double(Dependabot::Uv::FileParser, parse: top_level))
    allow(Dependabot::Uv::FileUpdater::LockFileUpdater).to receive(:new).and_return(lock_updater)
  end

  describe "#neighbours_in_lockfile?" do
    it "is true when another top-level dependency depends on it" do
      expect(resolver.neighbours_in_lockfile?).to be(true)
    end

    context "when the other top-level dependencies are unrelated" do
      let(:top_level) { [api, pinned("urllib3", "2.2.3")] }

      it { expect(resolver.neighbours_in_lockfile?).to be(false) }
    end
  end

  describe "#own_update_resolvable?" do
    it "rewrites only the dependency's pin and upgrades only it" do
      allow(lock_updater).to receive(:updated_dependency_files).and_return([resolved_lockfile])

      expect(resolver.own_update_resolvable?(target)).to be(true)
      expect(Dependabot::Uv::FileUpdater::LockFileUpdater).to have_received(:new).with(
        hash_including(upgrade_package_names: ["opentelemetry-api"])
      ) do |args|
        expect(args[:dependencies].map(&:name)).to eq(["opentelemetry-api"])
        expect(args[:dependencies].first.requirements.first[:requirement]).to eq("==1.26.0")
      end
      expect(resolver.rejected_version).to be_nil
    end

    it "records the version when uv reports a conflict" do
      allow(lock_updater).to receive(:updated_dependency_files).and_raise(conflict)

      expect(resolver.own_update_resolvable?(target)).to be(false)
      expect(resolver.rejected_version).to eq(target)
    end

    it "lets other errors through" do
      allow(lock_updater).to receive(:updated_dependency_files)
        .and_raise(Dependabot::PrivateSourceAuthenticationFailure.new("example.com"))

      expect { resolver.own_update_resolvable?(target) }
        .to raise_error(Dependabot::PrivateSourceAuthenticationFailure)
    end
  end

  describe "#updated_dependencies_after_full_unlock" do
    subject(:updates) { resolver.updated_dependencies_after_full_unlock(target) }

    it "relaxes the peers named in the conflict and returns both, dependency first" do
      calls = 0
      allow(lock_updater).to receive(:updated_dependency_files) do
        calls += 1
        raise conflict if calls == 1

        [resolved_lockfile]
      end

      expect(updates.map(&:name)).to eq(%w(opentelemetry-api opentelemetry-sdk))
      expect(updates.map(&:version)).to eq(%w(1.26.0 1.26.0))
      expect(updates.last.requirements.first[:requirement]).to eq("==1.26.0")
      expect(updates.last.previous_requirements.first[:requirement]).to eq("==1.25.0")
      expect(updates.last.previous_version).to eq("1.25.0")
      expect(Dependabot::Uv::FileUpdater::LockFileUpdater).to have_received(:new).with(
        hash_including(upgrade_package_names: ["opentelemetry-api"])
      ).twice
    end

    it "relaxes the peer to its locked version without upgrading it" do
      relaxed = nil
      calls = 0
      allow(Dependabot::Uv::FileUpdater::LockFileUpdater).to receive(:new) do |args|
        relaxed = args[:dependencies].find { |dep| dep.name == "opentelemetry-sdk" }
        lock_updater
      end
      allow(lock_updater).to receive(:updated_dependency_files) do
        calls += 1
        raise conflict if calls == 1

        [resolved_lockfile]
      end

      updates
      expect(relaxed.requirements.first[:requirement]).to eq(">=1.25.0")
      expect(relaxed.version).to be_nil
    end

    it "gives up when the conflict names no new peer" do
      allow(lock_updater).to receive(:updated_dependency_files).and_raise(
        Dependabot::UpdateNotPossible.new(%w(opentelemetry-api))
      )

      expect(updates).to be_nil
    end

    it "gives up when no peer moved" do
      calls = 0
      allow(lock_updater).to receive(:updated_dependency_files) do
        calls += 1
        raise conflict if calls == 1

        [Dependabot::DependencyFile.new(name: "uv.lock", content: bumped_lock(%w(opentelemetry-api)))]
      end

      expect(updates).to be_nil
    end

    context "when the peer is locked at several versions" do
      let(:lockfile) do
        content = fixture("uv_locks", "lockstep_pinned.lock")
        sdk_block = content[/\[\[package\]\]\nname = "opentelemetry-sdk".*?(?=\n\[\[package\]\])/m]
        Dependabot::DependencyFile.new(
          name: "uv.lock",
          content: content + "\n" + sdk_block.sub('version = "1.25.0"', 'version = "1.24.0"') + "\n"
        )
      end

      it "does not treat it as a peer" do
        allow(lock_updater).to receive(:updated_dependency_files).and_raise(conflict)

        expect(updates).to be_nil
      end
    end

    context "when the peer is declared twice with different extras" do
      let(:top_level) { [api, sdk, pinned("opentelemetry-sdk[extra]", "1.25.0")] }

      it "relaxes it once" do
        relaxed_names = []
        calls = 0
        allow(Dependabot::Uv::FileUpdater::LockFileUpdater).to receive(:new) do |args|
          relaxed_names = args[:dependencies].drop(1).map(&:name)
          lock_updater
        end
        allow(lock_updater).to receive(:updated_dependency_files) do
          calls += 1
          raise conflict if calls == 1

          [resolved_lockfile]
        end

        updates
        expect(relaxed_names).to eq(["opentelemetry-sdk"])
      end
    end
  end
end
