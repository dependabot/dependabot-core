# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency"
require "dependabot/dependency_file"
require "dependabot/package/release_cooldown_options"
require "dependabot/requirements_update_strategy"
require "dependabot/uv/update_checker/lockstep_resolver"

RSpec.describe Dependabot::Uv::UpdateChecker::LockstepResolver do
  let(:resolver) do
    described_class.new(
      dependency: dependency,
      dependency_files: dependency_files,
      credentials: [],
      repo_contents_path: nil,
      requirements_update_strategy: Dependabot::RequirementsUpdateStrategy::BumpVersions,
      update_cooldown: update_cooldown
    )
  end
  let(:dependency) { api }
  let(:update_cooldown) { nil }

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

  # Stands in for uv: the block gets the names passed to the lock updater and returns its files or raises
  def stub_uv
    allow(Dependabot::Uv::FileUpdater::LockFileUpdater).to receive(:new) do |args|
      updater = instance_double(Dependabot::Uv::FileUpdater::LockFileUpdater)
      allow(updater).to receive(:updated_dependency_files) { yield(args[:dependencies].map(&:name)) }
      updater
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

    context "when the dependency itself depends on another top-level dependency" do
      let(:dependency) { sdk }

      it { expect(resolver.neighbours_in_lockfile?).to be(true) }
    end
  end

  describe "#lockstep_conflict?" do
    it "rewrites only the dependency's pin and upgrades only it" do
      allow(lock_updater).to receive(:updated_dependency_files).and_return([resolved_lockfile])

      expect(resolver.lockstep_conflict?(target)).to be(false)
      expect(Dependabot::Uv::FileUpdater::LockFileUpdater).to have_received(:new).with(
        hash_including(upgrade_package_names: ["opentelemetry-api"])
      ) do |args|
        expect(args[:dependencies].map(&:name)).to eq(["opentelemetry-api"])
        expect(args[:dependencies].first.requirements.first[:requirement]).to eq("==1.26.0")
      end
      expect(resolver.rejected_version).to be_nil
    end

    it "records the version when uv's conflict names another direct dependency" do
      allow(lock_updater).to receive(:updated_dependency_files).and_raise(conflict)

      expect(resolver.lockstep_conflict?(target)).to be(true)
      expect(resolver.rejected_version).to eq(target)
    end

    it "doesn't count a conflict that names no other direct dependency" do
      allow(lock_updater).to receive(:updated_dependency_files).and_raise(
        Dependabot::DependencyFileNotResolvable,
        "× No solution found when resolving dependencies:\n" \
        "╰─▶ Because the current Python version (3.10.12) does not satisfy Python>=3.12 and " \
        "opentelemetry-api==1.26.0 depends on Python>=3.12, we can conclude that opentelemetry-api==1.26.0 " \
        "cannot be used. And because your project depends on opentelemetry-api==1.26.0, we can conclude " \
        "that your project's requirements are unsatisfiable."
      )

      expect(resolver.lockstep_conflict?(target)).to be(false)
      expect(resolver.rejected_version).to be_nil
    end

    context "when the only other dependency named is not a peer" do
      before { allow(lock_updater).to receive(:updated_dependency_files).and_raise(conflict) }

      context "when it is only a build-system requirement" do
        let(:sdk) do
          Dependabot::Dependency.new(
            name: "opentelemetry-sdk",
            version: "1.25.0",
            requirements: [{ file: "pyproject.toml", requirement: "==1.25.0", groups: ["build-system"], source: nil }],
            package_manager: "uv"
          )
        end

        it { expect(resolver.lockstep_conflict?(target)).to be(false) }
      end

      context "when it is a local package" do
        let(:lockfile) do
          content = fixture("uv_locks", "lockstep_pinned.lock").sub(
            "name = \"opentelemetry-sdk\"\nversion = \"1.25.0\"\nsource = { registry = \"https://pypi.org/simple\" }",
            "name = \"opentelemetry-sdk\"\nversion = \"1.25.0\"\nsource = { editable = \"sdk\" }"
          )
          Dependabot::DependencyFile.new(name: "uv.lock", content: content)
        end

        it { expect(resolver.lockstep_conflict?(target)).to be(false) }
      end

      context "when it has no version" do
        let(:sdk) do
          Dependabot::Dependency.new(
            name: "opentelemetry-sdk",
            version: nil,
            requirements: [{ file: "pyproject.toml", requirement: ">=1.25.0", groups: [], source: nil }],
            package_manager: "uv"
          )
        end

        it { expect(resolver.lockstep_conflict?(target)).to be(false) }
      end
    end

    it "lets other errors through" do
      allow(lock_updater).to receive(:updated_dependency_files)
        .and_raise(Dependabot::PrivateSourceAuthenticationFailure.new("example.com"))

      expect { resolver.lockstep_conflict?(target) }
        .to raise_error(Dependabot::PrivateSourceAuthenticationFailure)
    end

    it "reuses its uv run as the first round of the full unlock" do
      stub_uv do |names|
        raise conflict unless names.include?("opentelemetry-sdk")

        [resolved_lockfile]
      end

      resolver.lockstep_conflict?(target)
      updates = resolver.updated_dependencies_after_full_unlock(target)

      expect(updates.map(&:name)).to eq(%w(opentelemetry-api opentelemetry-sdk))
      expect(Dependabot::Uv::FileUpdater::LockFileUpdater).to have_received(:new).twice
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

    context "when the peer only appears further down uv's derivation" do
      let(:message) do
        <<~ERROR
          × No solution found when resolving dependencies:
          ╰─▶ Because opentelemetry-semantic-conventions==0.46b0 depends on opentelemetry-api==1.25.0 and your
              project depends on opentelemetry-api==1.26.0, we can conclude that
              opentelemetry-semantic-conventions==0.46b0 cannot be used.
              And because opentelemetry-sdk==1.25.0 depends on opentelemetry-semantic-conventions==0.46b0 and
              your project depends on opentelemetry-sdk==1.25.0, we can conclude that your project's
              requirements are unsatisfiable.
        ERROR
      end

      it "reads the peer from the uv output behind the conflict" do
        relaxed = nil
        calls = 0
        allow(Dependabot::Uv::FileUpdater::LockFileUpdater).to receive(:new) do |args|
          relaxed ||= args[:dependencies].find { |dep| dep.name == "opentelemetry-sdk" }
          lock_updater
        end
        allow(lock_updater).to receive(:updated_dependency_files) do
          calls += 1
          if calls == 1
            begin
              raise Dependabot::SharedHelpers::HelperSubprocessFailed.new(message: message, error_context: {})
            rescue StandardError
              raise Dependabot::UpdateNotPossible, %w(opentelemetry-semantic-conventions opentelemetry-api)
            end
          end

          [resolved_lockfile]
        end

        expect(updates.map(&:name)).to eq(%w(opentelemetry-api opentelemetry-sdk))
        expect(relaxed.requirements.first[:requirement]).to eq(">=1.25.0")
      end
    end

    it "relaxes the peers named in an unresolvable uv conflict" do
      calls = 0
      allow(lock_updater).to receive(:updated_dependency_files) do
        calls += 1
        if calls == 1
          raise Dependabot::DependencyFileNotResolvable,
                "× No solution found when resolving dependencies:\n" \
                "╰─▶ Because opentelemetry-sdk==1.25.0 depends on opentelemetry-api==1.25.0 and your project " \
                "depends on opentelemetry-api==1.26.0, we can conclude that your project's requirements are " \
                "unsatisfiable."
        end

        [resolved_lockfile]
      end

      expect(updates.map(&:name)).to eq(%w(opentelemetry-api opentelemetry-sdk))
    end

    it "lets unresolvable errors that aren't conflicts through" do
      allow(lock_updater).to receive(:updated_dependency_files)
        .and_raise(Dependabot::DependencyFileNotResolvable.new("Failed to build foo"))

      expect { updates }.to raise_error(Dependabot::DependencyFileNotResolvable, "Failed to build foo")
    end

    it "gives up when the conflict names no new peer" do
      stub_uv do |names|
        raise conflict unless names.include?("opentelemetry-sdk")

        raise Dependabot::UpdateNotPossible, %w(opentelemetry-sdk opentelemetry-api)
      end

      expect(updates).to be_nil
      expect(Dependabot::Uv::FileUpdater::LockFileUpdater).to have_received(:new).twice
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

    context "when uv forks the peer onto several versions" do
      let(:forked_lockfile) do
        content = bumped_lock(%w(opentelemetry-api opentelemetry-sdk))
        sdk_block = content[/\[\[package\]\]\nname = "opentelemetry-sdk".*?(?=\n\[\[package\]\])/m]
        Dependabot::DependencyFile.new(
          name: "uv.lock",
          content: content + "\n" + sdk_block.sub('version = "1.26.0"', 'version = "1.25.0"') + "\n"
        )
      end

      it "gives up, since a single pin can't express it" do
        stub_uv do |names|
          raise conflict unless names.include?("opentelemetry-sdk")

          [forked_lockfile]
        end

        expect(updates).to be_nil
      end
    end

    context "when the dependency is the one depending on its peer" do
      let(:dependency) { sdk }

      it "moves the peer it depends on, dependency first" do
        stub_uv do |names|
          raise Dependabot::UpdateNotPossible, %w(opentelemetry-sdk opentelemetry-api) unless
            names.include?("opentelemetry-api")

          [resolved_lockfile]
        end

        expect(updates.map(&:name)).to eq(%w(opentelemetry-sdk opentelemetry-api))
        expect(updates.map(&:version)).to eq(%w(1.26.0 1.26.0))
      end
    end

    context "when each round's conflict names another peer" do
      let(:semantic_conventions) { pinned("opentelemetry-semantic-conventions", "0.46b0") }
      let(:top_level) { [api, sdk, semantic_conventions] }
      let(:all_bumped) do
        content = bumped_lock(%w(opentelemetry-api opentelemetry-sdk)).sub(
          "name = \"opentelemetry-semantic-conventions\"\nversion = \"0.46b0\"",
          "name = \"opentelemetry-semantic-conventions\"\nversion = \"0.47b0\""
        )
        Dependabot::DependencyFile.new(name: "uv.lock", content: content)
      end

      it "relaxes them all and returns every moved peer, sorted by name" do
        rounds = []
        stub_uv do |names|
          rounds << names
          case names.length
          when 1 then raise Dependabot::UpdateNotPossible, %w(opentelemetry-semantic-conventions opentelemetry-api)
          when 2 then raise Dependabot::UpdateNotPossible, %w(opentelemetry-sdk opentelemetry-api)
          else [all_bumped]
          end
        end

        expect(updates.map(&:name))
          .to eq(%w(opentelemetry-api opentelemetry-sdk opentelemetry-semantic-conventions))
        expect(updates.map(&:version)).to eq(%w(1.26.0 1.26.0 0.47b0))
        expect(rounds.last).to eq(%w(opentelemetry-api opentelemetry-semantic-conventions opentelemetry-sdk))
      end
    end

    context "with a cooldown" do
      let(:update_cooldown) { Dependabot::Package::ReleaseCooldownOptions.new(default_days: 7) }
      let(:latest_version_finder) do
        instance_double(Dependabot::Uv::UpdateChecker::LatestVersionFinder, latest_version: latest_allowed)
      end

      before do
        allow(Dependabot::Uv::UpdateChecker::LatestVersionFinder).to receive(:new).and_return(latest_version_finder)
        stub_uv do |names|
          raise conflict unless names.include?("opentelemetry-sdk")

          [resolved_lockfile]
        end
      end

      context "when the peer's new version is still cooling down" do
        let(:latest_allowed) { Dependabot::Uv::Version.new("1.25.0") }

        it { expect(updates).to be_nil }
      end

      context "when the peer's new version is out of the cooldown window" do
        let(:latest_allowed) { Dependabot::Uv::Version.new("1.26.0") }

        it "moves the peer" do
          expect(updates.map(&:name)).to eq(%w(opentelemetry-api opentelemetry-sdk))
          expect(Dependabot::Uv::UpdateChecker::LatestVersionFinder).to have_received(:new).with(
            hash_including(cooldown_options: update_cooldown, ignored_versions: [])
          ) { |args| expect(args[:dependency].name).to eq("opentelemetry-sdk") }
        end
      end
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
        stub_uv do |names|
          raise conflict unless names.include?("opentelemetry-sdk")

          [resolved_lockfile]
        end

        expect(updates).to be_nil
        expect(Dependabot::Uv::FileUpdater::LockFileUpdater).to have_received(:new).once
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
