# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency_change_builder"
require "dependabot/dependency_file"
require "dependabot/job"

require "dependabot/bundler"

RSpec.describe Dependabot::DependencyChangeBuilder do
  let(:job) do
    instance_double(
      Dependabot::Job,
      package_manager: "bundler",
      repo_contents_path: nil,
      credentials: [
        {
          "type" => "git_source",
          "host" => "github.com",
          "username" => "x-access-token",
          "password" => "github-token"
        }
      ],
      experiments: {},
      security_updates_only?: false,
      cooldown: nil,
      blocked_versions: [],
      reject_external_code?: false,
      source: source
    )
  end

  let(:source) { Dependabot::Source.new(provider: "github", repo: "gocardless/bump", directory: "/.") }

  let(:dependency_files) do
    [
      Dependabot::DependencyFile.new(
        name: "Gemfile",
        content: fixture("bundler/original/Gemfile"),
        directory: "/",
        support_file: false
      ),
      Dependabot::DependencyFile.new(
        name: "Gemfile.lock",
        content: fixture("bundler/original/Gemfile.lock"),
        directory: "/",
        support_file: false
      ),
      Dependabot::DependencyFile.new(
        name: "sub_dep",
        content: fixture("bundler/original/sub_dep"),
        directory: "/",
        support_file: true
      ),
      Dependabot::DependencyFile.new(
        name: "sub_dep.lock",
        content: fixture("bundler/original/sub_dep.lock"),
        directory: "/",
        support_file: true
      )
    ]
  end

  let(:updated_dependencies) do
    [build_dependency(name: "dummy-pkg-b", version: "1.2.0", previous_version: "1.1.0")]
  end

  describe "::create_from" do
    subject(:create_change) do
      described_class.create_from(
        job: job,
        dependency_files: dependency_files,
        updated_dependencies: updated_dependencies,
        change_source: change_source,
        notices: notices
      )
    end

    let(:notices) { [] }
    let(:lead_dependency_change_source) { build_dependency(name: "dummy-pkg-b", version: "1.1.0") }
    let(:single_dependency_info) { "dummy-pkg-b (1.1.0 → 1.2.0)" }
    let(:file_updater_class) { class_double(Dependabot::Bundler::FileUpdater) }

    def stub_file_updater(updated_dependency_files:, notices: [])
      file_updater = instance_double(
        Dependabot::Bundler::FileUpdater,
        updated_dependency_files: updated_dependency_files,
        notices: notices
      )

      allow(Dependabot::FileUpdaters).to receive(:for_package_manager)
        .with("bundler")
        .and_return(file_updater_class)
      allow(file_updater_class).to receive(:new).and_return(file_updater)
    end

    def build_dependency(name:, version:, previous_version: nil)
      requirement = {
        file: "Gemfile",
        requirement: "~> #{version}",
        groups: [],
        source: nil
      }

      dependency_args = {
        name: name,
        package_manager: "bundler",
        version: version,
        requirements: [requirement]
      }

      if previous_version
        previous_requirement = {
          file: "Gemfile",
          requirement: "~> #{previous_version}",
          groups: [],
          source: nil
        }

        dependency_args[:previous_version] = previous_version
        dependency_args[:previous_requirements] = [previous_requirement]
      end

      Dependabot::Dependency.new(**dependency_args)
    end

    def dependency_group_source
      Dependabot::DependencyGroup.new(name: "dummy-pkg-*", rules: { patterns: ["dummy-pkg-*"] })
    end

    context "when the job is a security update" do
      let(:change_source) { lead_dependency_change_source }

      before do
        allow(job).to receive(:security_updates_only?).and_return(true)
        stub_file_updater(updated_dependency_files: dependency_files.reject(&:support_file?))
      end

      it "passes security_updates_only: true in options to the file updater" do
        create_change

        expect(file_updater_class).to have_received(:new).with(
          hash_including(options: hash_including(security_updates_only: true))
        )
      end
    end

    context "when the job is not a security update" do
      let(:change_source) { lead_dependency_change_source }

      before do
        allow(job).to receive(:security_updates_only?).and_return(false)
        stub_file_updater(updated_dependency_files: dependency_files.reject(&:support_file?))
      end

      it "passes security_updates_only: false in options to the file updater" do
        create_change

        expect(file_updater_class).to have_received(:new).with(
          hash_including(options: hash_including(security_updates_only: false))
        )
      end
    end

    context "when the source is a lead dependency" do
      let(:change_source) { lead_dependency_change_source }

      it "creates a new DependencyChange with the updated files" do
        dependency_change = create_change

        expect(dependency_change).to be_a(Dependabot::DependencyChange)
        expect(dependency_change.updated_dependencies).to eql(updated_dependencies)
        expect(dependency_change.updated_dependency_files.map(&:name)).to eql(["Gemfile", "Gemfile.lock"])
        expect(dependency_change).not_to be_grouped_update

        gemfile = dependency_change.updated_dependency_files.find { |file| file.name == "Gemfile" }
        expect(gemfile.content).to eql(fixture("bundler/updated/Gemfile"))

        lockfile = dependency_change.updated_dependency_files.find { |file| file.name == "Gemfile.lock" }
        expect(lockfile.content).to eql(fixture("bundler/updated/Gemfile.lock"))
      end

      it "does not include support files in the updated files" do
        stub_file_updater(updated_dependency_files: dependency_files)

        dependency_change = described_class.create_from(
          job: job,
          dependency_files: dependency_files,
          updated_dependencies: updated_dependencies,
          change_source: change_source
        )

        updated_file_names = dependency_change.updated_dependency_files.map(&:name)
        expect(updated_file_names).not_to include("sub_dep", "sub_dep.lock")
      end
    end

    context "when the source is a dependency group" do
      let(:change_source) { dependency_group_source }

      it "creates a new DependencyChange flagged as a grouped update" do
        dependency_change = create_change

        expect(dependency_change).to be_a(Dependabot::DependencyChange)
        expect(dependency_change).to be_grouped_update
      end
    end

    context "when there are no file changes" do
      let(:change_source) { lead_dependency_change_source }

      before do
        stub_file_updater(updated_dependency_files: [])
      end

      it "raises an exception with diagnostic dependency details" do
        expect { create_change }
          .to raise_error(
            Dependabot::DependabotError,
            "FileUpdater failed to update any files for: dummy-pkg-b (1.1.0 → 1.2.0)"
          )
      end
    end

    context "when multiple dependencies have no file changes" do
      let(:updated_dependencies) do
        [
          build_dependency(name: "dummy-pkg-b", version: "1.2.0", previous_version: "1.1.0"),
          build_dependency(name: "dummy-pkg-a", version: "2.0.0", previous_version: "1.9.0")
        ]
      end

      let(:change_source) { dependency_group_source }

      before do
        stub_file_updater(updated_dependency_files: [])
      end

      it "raises an exception listing dependency names" do
        expect { create_change }
          .to raise_error(
            Dependabot::DependabotError,
            "FileUpdater failed to update any files for: dummy-pkg-a, dummy-pkg-b"
          )
      end
    end

    context "when duplicate dependency names have no file changes" do
      let(:updated_dependencies) do
        [
          build_dependency(name: "dummy-pkg-b", version: "1.2.0", previous_version: "1.1.0"),
          build_dependency(name: "dummy-pkg-b", version: "1.3.0", previous_version: "1.2.0")
        ]
      end

      let(:change_source) { dependency_group_source }

      before do
        stub_file_updater(updated_dependency_files: [])
      end

      it "raises an exception with unique dependency names" do
        expect { create_change }
          .to raise_error(
            Dependabot::DependabotError,
            "FileUpdater failed to update any files for: dummy-pkg-b"
          )
      end
    end

    context "when only support files are returned" do
      let(:change_source) { lead_dependency_change_source }
      let(:support_files) { dependency_files.select(&:support_file?) }
      let(:updated_support_files) { [support_files.last, support_files.first, support_files.last] }
      let(:updater_notices) { [instance_double(Dependabot::Notice)] }

      before do
        stub_file_updater(updated_dependency_files: updated_support_files, notices: updater_notices)
      end

      it "includes support files as primary update targets" do
        dependency_change = create_change

        expect(dependency_change).to be_a(Dependabot::DependencyChange)
        expect(dependency_change.updated_dependency_files.map(&:name))
          .to eq(updated_support_files.map(&:name))
      end

      it "collects notices" do
        create_change
        expect(notices).to eq(updater_notices)
      end
    end

    context "when grouped updates return only support files" do
      let(:updated_dependencies) do
        [
          build_dependency(name: "dummy-pkg-b", version: "1.2.0", previous_version: "1.1.0"),
          build_dependency(name: "dummy-pkg-a", version: "2.0.0", previous_version: "1.9.0"),
          build_dependency(name: "dummy-pkg-b", version: "1.3.0", previous_version: "1.2.0")
        ]
      end
      let(:change_source) { dependency_group_source }
      let(:support_files) { dependency_files.select(&:support_file?) }

      before do
        stub_file_updater(updated_dependency_files: support_files)
      end

      it "includes support files as primary update targets" do
        dependency_change = create_change

        expect(dependency_change).to be_a(Dependabot::DependencyChange)
        expect(dependency_change.updated_dependency_files.map(&:name))
          .to eq(support_files.map(&:name))
      end
    end
  end

  describe "blocking transitive dependency versions" do
    subject(:create_change) do
      described_class.create_from(
        job: job,
        dependency_files: dependency_files,
        updated_dependencies: updated_dependencies,
        change_source: change_source
      )
    end

    let(:change_source) { direct_dep("dummy-pkg-b", "1.1.0") }
    let(:updated_dependencies) { [direct_dep("dummy-pkg-b", "1.2.0", previous_version: "1.1.0")] }

    let(:file_updater_class) { class_double(Dependabot::Bundler::FileUpdater) }
    let(:parser_class) { class_double(Dependabot::Bundler::FileParser) }
    let(:parser) { instance_double(Dependabot::Bundler::FileParser) }

    let(:previous_dependencies) { [transitive_dep("transitive-dep", "1.0.0")] }
    let(:current_dependencies) { [transitive_dep("transitive-dep", "1.5.0")] }

    def direct_dep(name, version, previous_version: nil)
      args = {
        name: name,
        package_manager: "bundler",
        version: version,
        requirements: [{ file: "Gemfile", requirement: "~> #{version}", groups: [], source: nil }]
      }
      if previous_version
        args[:previous_version] = previous_version
        args[:previous_requirements] = [
          { file: "Gemfile", requirement: "~> #{previous_version}", groups: [], source: nil }
        ]
      end
      Dependabot::Dependency.new(**args)
    end

    def transitive_dep(name, version)
      Dependabot::Dependency.new(name: name, version: version, requirements: [], package_manager: "bundler")
    end

    def blocked_entry(name:, requirement:, reason: nil)
      Dependabot::Job::BlockedVersion.from_hash(
        { "dependency-name" => name, "version-requirement" => requirement, "reason" => reason }.compact
      )
    end

    before do
      Dependabot::Experiments.register(:blocked_versions, true)

      file_updater = instance_double(
        Dependabot::Bundler::FileUpdater,
        updated_dependency_files: dependency_files.reject(&:support_file?),
        notices: []
      )
      allow(Dependabot::FileUpdaters).to receive(:for_package_manager)
        .with("bundler").and_return(file_updater_class)
      allow(file_updater_class).to receive(:new).and_return(file_updater)

      allow(Dependabot::FileParsers).to receive(:for_package_manager)
        .with("bundler").and_return(parser_class)
      allow(parser_class).to receive(:new).and_return(parser)
      allow(parser).to receive(:parse).and_return(previous_dependencies, current_dependencies)
    end

    after { Dependabot::Experiments.reset! }

    context "when a transitive dependency changes to a blocked version" do
      before do
        allow(job).to receive(:blocked_versions)
          .and_return([blocked_entry(name: "transitive-dep", requirement: "= 1.5.0", reason: "malware")])
      end

      it "raises BlockedDependencyVersion with details and does not create a change" do
        expect { create_change }.to raise_error(Dependabot::BlockedDependencyVersion) do |error|
          expect(error.dependency_name).to eq("transitive-dep")
          expect(error.blocked_version).to eq("1.5.0")
          expect(error.version_requirement).to eq("= 1.5.0")
          expect(error.reason).to eq("malware")
        end
      end
    end

    context "when a transitive dependency changes to an allowed version" do
      before do
        allow(job).to receive(:blocked_versions)
          .and_return([blocked_entry(name: "transitive-dep", requirement: "= 9.9.9")])
      end

      it "creates the change without raising" do
        expect(create_change).to be_a(Dependabot::DependencyChange)
      end

      it "logs a summary at info and the per-dependency detail at debug" do
        allow(Dependabot.logger).to receive(:info)
        allow(Dependabot.logger).to receive(:debug)
        create_change
        expect(Dependabot.logger).to have_received(:info)
          .with(/Regenerating the lockfile changed 1 transitive dependency/)
        expect(Dependabot.logger).to have_received(:debug).with(/transitive-dep 1\.0\.0 => 1\.5\.0/)
      end
    end

    context "when the blocked_versions experiment is disabled" do
      before do
        Dependabot::Experiments.reset!
        allow(job).to receive(:blocked_versions)
          .and_return([blocked_entry(name: "transitive-dep", requirement: "= 1.5.0")])
      end

      it "does not re-parse files or block the update" do
        expect(create_change).to be_a(Dependabot::DependencyChange)
        expect(Dependabot::FileParsers).not_to have_received(:for_package_manager)
      end
    end

    context "when no blocked versions are configured" do
      before do
        allow(job).to receive(:blocked_versions).and_return([])
      end

      it "does not re-parse files and creates the change" do
        expect(create_change).to be_a(Dependabot::DependencyChange)
        expect(Dependabot::FileParsers).not_to have_received(:for_package_manager)
      end
    end
  end
end
