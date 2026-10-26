# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/updater/group_update_creation"
require "dependabot/dependency_snapshot"
require "dependabot/updater/error_handler"
require "dependabot/job"
require "dependabot/dependency_group"
require "dependabot/dependency"
require "dependabot/notices"
require "dependabot/update_checkers/base"
require "dependabot/experiments"
require "dependabot/service"

RSpec.describe Dependabot::Updater::GroupUpdateCreation do
  # Create a test class that includes the module to test it
  let(:test_class) do
    Class.new do
      include Dependabot::Updater::GroupUpdateCreation

      attr_reader :dependency_snapshot, :error_handler, :job, :group, :service

      def initialize(dependency_snapshot, error_handler, job, group, service)
        @dependency_snapshot = dependency_snapshot
        @error_handler = error_handler
        @job = job
        @group = group
        @service = service
      end
    end
  end

  let(:service) { instance_double(Dependabot::Service, record_update_job_error: nil) }
  let(:test_instance) { test_class.new(dependency_snapshot, error_handler, job, group, service) }

  let(:dependency_snapshot) do
    instance_double(
      Dependabot::DependencySnapshot,
      dependencies: dependencies,
      all_dependencies: all_dependencies,
      dependency_files: dependency_files,
      handled_dependencies: [],
      notices: []
    ).tap do |snapshot|
      allow(snapshot).to receive(:add_handled_dependencies)
    end
  end

  let(:error_handler) do
    instance_double(Dependabot::Updater::ErrorHandler).tap do |handler|
      allow(handler).to receive(:handle_job_error)
    end
  end

  let(:job) do
    instance_double(
      Dependabot::Job,
      dependencies: job_dependencies,
      package_manager: "bundler",
      clone?: clone_job,
      repo_contents_path: repo_contents_path,
      security_advisories_for: security_advisories,
      updating_a_pull_request?: false,
      blocked_versions_for?: false,
      dependency_group_to_refresh: nil,
      source: source
    )
  end

  let(:clone_job) { false }
  let(:repo_contents_path) { nil }
  let(:source_directory) { "/" }
  let(:source) { instance_double(Dependabot::Source, directory: source_directory) }

  let(:group) do
    instance_double(
      Dependabot::DependencyGroup,
      name: "test-group",
      dependencies: group_dependencies,
      group_by_dependency_name?: false
    )
  end

  let(:dependencies) do
    [
      instance_double(
        Dependabot::Dependency,
        name: "dep1",
        version: "1.0.0",
        all_versions: ["1.0.0"],
        requirements: [],
        metadata: {}
      ),
      instance_double(
        Dependabot::Dependency,
        name: "dep2",
        version: "2.0.0",
        all_versions: ["2.0.0"],
        requirements: [],
        metadata: {}
      )
    ]
  end

  let(:group_dependencies) do
    [dependencies.first]
  end

  let(:dependency_files) do
    [instance_double(Dependabot::DependencyFile, name: "Gemfile")]
  end

  let(:job_dependencies) { ["dep1"] }
  let(:all_dependencies) { dependencies }
  let(:security_advisories) { [] }

  let(:security_advisory) do
    Dependabot::SecurityAdvisory.new(
      dependency_name: "dep1",
      package_manager: "dummy",
      vulnerable_versions: ["<= 1.0.0"]
    )
  end

  let(:advisory_checker) do
    Dependabot::UpdateCheckers::Base.new(
      dependency: dependency,
      dependency_files: [],
      credentials: [],
      security_advisories: security_advisories
    )
  end

  let(:checker) do
    instance_double(
      Dependabot::UpdateCheckers::Base,
      dependency: dependencies.first,
      up_to_date?: false,
      vulnerable?: true,
      lowest_resolvable_security_fix_version: nil,
      lowest_security_fix_version: "3.0.0",
      conflicting_dependencies: [],
      respond_to?: false
    )
  end

  before do
    # Stub all experiment flags to avoid unexpected argument errors
    allow(Dependabot::Experiments).to receive(:enabled?).and_call_original

    # Stub common methods that would be called
    allow(test_instance).to receive_messages(
      prepare_workspace: nil,
      cleanup_workspace: nil
    )
    allow(test_instance).to receive_messages(
      dependency_file_parser: instance_double(Dependabot::FileParsers::Base, parse: dependencies),
      service: service
    )
    allow(Dependabot.logger).to receive(:info)

    # Reset experiments before each test
    Dependabot::Experiments.reset!
  end

  after do
    Dependabot::Experiments.reset!
  end

  describe "#note_security_update_not_possible" do
    let(:dependency) { dependencies.first }

    context "when recording security update errors" do
      context "when dependency has security advisories" do
        let(:security_advisories) { [{ "id" => "advisory-1" }] }

        before do
          allow(job).to receive(:security_advisories_for).with(dependency).and_return(security_advisories)
        end

        it "logs and records security update error when no conflicting dependencies" do
          expect(Dependabot.logger).to receive(:info).with(
            "Security update not possible for #{dependency.name} in group #{group.name}"
          )
          expect(service).to receive(:record_update_job_error).with(
            error_type: "security_update_not_possible",
            error_details: hash_including("dependency-name": dependency.name),
            dependency: nil
          )

          test_instance.note_security_update_not_possible(dependency, checker, group)
          test_instance.report_security_update_failure(dependency.name)
        end

        it "does not record a security error when the dependency is not vulnerable" do
          allow(checker).to receive(:vulnerable?).and_return(false)
          expect(checker).not_to receive(:lowest_resolvable_security_fix_version)
          expect(service).not_to receive(:record_update_job_error)

          test_instance.note_security_update_not_possible(dependency, checker, group)
          test_instance.report_security_update_failure(dependency.name)
        end

        it "logs every detected version and requirement for the dependency" do
          requirements = [
            Dependabot::DependencyRequirement.create(file: "package.json", requirement: "^1.0.0"),
            Dependabot::DependencyRequirement.create(file: "package-lock.json", requirement: "^2.0.0")
          ]
          allow(dependency).to receive_messages(
            all_versions: %w(1.0.0 2.0.0),
            requirements: requirements
          )
          expect(Dependabot.logger).to receive(:info).with(
            'Security advisory check for dep1: versions=["1.0.0", "2.0.0"], ' \
            'requirements=["package.json: ^1.0.0", "package-lock.json: ^2.0.0"]'
          )

          test_instance.note_security_update_not_possible(dependency, checker, group)
        end

        context "when checker has conflicting dependencies with vulnerability explanation" do
          before do
            allow(checker).to receive(:respond_to?).with(:conflicting_dependencies).and_return(true)
            allow(checker).to receive(:conflicting_dependencies).and_return(conflicting_deps)
          end

          let(:conflicting_deps) do
            [{ "explanation" => "Vulnerability fix not available" }]
          end

          it "logs specific explanation and records error" do
            expect(Dependabot.logger).to receive(:info).with(
              "Security update not possible for #{dependency.name} in group #{group.name}: " \
              "Vulnerability fix not available"
            )
            expect(service).to receive(:record_update_job_error).with(
              error_type: "security_update_not_possible",
              error_details: hash_including("conflicting-dependencies": conflicting_deps),
              dependency: nil
            )

            test_instance.note_security_update_not_possible(dependency, checker, group)
            test_instance.report_security_update_failure(dependency.name)
          end
        end

        context "when checker has conflicting dependencies without vulnerability explanation" do
          before do
            allow(checker).to receive(:respond_to?).with(:conflicting_dependencies).and_return(true)
            allow(checker).to receive(:conflicting_dependencies).and_return(conflicting_deps)
          end

          let(:conflicting_deps) do
            [{ "dependency_name" => "other_dep", "explanation" => "Regular conflict" }]
          end

          it "logs generic message and records error" do
            expect(Dependabot.logger).to receive(:info).with(
              "Security update not possible for #{dependency.name} in group #{group.name}"
            )
            expect(service).to receive(:record_update_job_error).with(
              error_type: "security_update_not_possible",
              error_details: hash_including("conflicting-dependencies": conflicting_deps),
              dependency: nil
            )

            test_instance.note_security_update_not_possible(dependency, checker, group)
            test_instance.report_security_update_failure(dependency.name)
          end
        end
      end

      context "when dependency has no security advisories" do
        let(:security_advisories) { [] }

        before do
          allow(job).to receive(:security_advisories_for).with(dependency).and_return(security_advisories)
        end

        it "does not log or record any error" do
          expect(Dependabot.logger).not_to receive(:info)
          expect(service).not_to receive(:record_update_job_error)

          test_instance.note_security_update_not_possible(dependency, checker, group)
          test_instance.report_security_update_failure(dependency.name)
        end
      end
    end
  end

  describe "#note_security_update_not_found" do
    let(:dependency) { dependencies.first }

    context "when recording missing security updates" do
      context "when dependency has security advisories" do
        let(:security_advisories) { [{ "id" => "advisory-1" }] }

        before do
          allow(job).to receive(:security_advisories_for).with(dependency).and_return(security_advisories)
        end

        it "logs and records security update not found error" do
          expect(Dependabot.logger).to receive(:info).with(
            "Security update not found for #{dependency.name} in group #{group.name} - " \
            "dependency is up to date but still vulnerable"
          )
          expect(service).to receive(:record_update_job_error).with(
            error_type: "security_update_not_found",
            error_details: { "dependency-name": dependency.name, "dependency-version": dependency.version },
            dependency: dependency
          )

          test_instance.note_security_update_not_found(dependency, checker, group)
          test_instance.report_security_update_failure(dependency.name)
        end
      end

      context "when dependency has no security advisories" do
        let(:security_advisories) { [] }

        before do
          allow(job).to receive(:security_advisories_for).with(dependency).and_return(security_advisories)
        end

        it "does not log or record any error" do
          expect(Dependabot.logger).not_to receive(:info)
          expect(service).not_to receive(:record_update_job_error)

          test_instance.note_security_update_not_found(dependency, checker, group)
          test_instance.report_security_update_failure(dependency.name)
        end
      end

      context "when the installed version is outside the advisory range" do
        let(:dependency) do
          Dependabot::Dependency.new(
            name: "dep1",
            version: "2.0.0",
            requirements: [],
            package_manager: "dummy"
          )
        end
        let(:checker) { advisory_checker }
        let(:security_advisories) { [security_advisory] }

        it "does not record a security update not found error" do
          expect(service).not_to receive(:record_update_job_error)

          test_instance.note_security_update_not_found(dependency, checker, group)
          test_instance.report_security_update_failure(dependency.name)
        end
      end
    end
  end

  describe "#note_security_update_ignored" do
    let(:dependency) { dependencies.first }

    context "when recording ignored security updates" do
      context "when dependency has security advisories" do
        let(:security_advisories) { [{ "id" => "advisory-1" }] }

        before do
          allow(job).to receive(:security_advisories_for).with(dependency).and_return(security_advisories)
        end

        it "logs and records security update ignored error" do
          expect(Dependabot.logger).to receive(:info).with(
            "All versions ignored for #{dependency.name} in group #{group.name} but security advisories exist"
          )
          expect(service).to receive(:record_update_job_error).with(
            error_type: "all_versions_ignored", error_details: { "dependency-name": dependency.name }, dependency: nil
          )

          test_instance.note_security_update_ignored(dependency, checker, group)
          test_instance.report_security_update_failure(dependency.name)
        end
      end

      context "when dependency has no security advisories" do
        let(:security_advisories) { [] }

        before do
          allow(job).to receive(:security_advisories_for).with(dependency).and_return(security_advisories)
        end

        it "does not log or record any error" do
          expect(Dependabot.logger).not_to receive(:info)
          expect(service).not_to receive(:record_update_job_error)

          test_instance.note_security_update_ignored(dependency, checker, group)
          test_instance.report_security_update_failure(dependency.name)
        end
      end

      context "when the installed version is outside the advisory range" do
        let(:dependency) do
          Dependabot::Dependency.new(
            name: "dep1",
            version: "2.0.0",
            requirements: [],
            package_manager: "dummy"
          )
        end
        let(:checker) { advisory_checker }
        let(:security_advisories) { [security_advisory] }

        it "does not record an ignored security update error" do
          expect(service).not_to receive(:record_update_job_error)

          test_instance.note_security_update_ignored(dependency, checker, group)
          test_instance.report_security_update_failure(dependency.name)
        end
      end
    end
  end

  describe "#report_security_update_failures" do
    let(:dependency) { dependencies.first }

    before do
      allow(job).to receive_messages(security_updates_only?: true)
      allow(job).to receive(:security_advisories_for).with(dependency).and_return([{ "id" => "advisory-1" }])
      allow(Dependabot.logger).to receive(:info)
      test_instance.note_security_update_not_possible(dependency, checker, group)
    end

    it "does not report a dependency that was updated in another directory" do
      updated = instance_double(Dependabot::Dependency, name: "dep1")
      dependency_change = instance_double(Dependabot::DependencyChange, updated_dependencies: [updated])

      expect(service).not_to receive(:record_update_job_error)

      test_instance.report_security_update_failures(dependency_change)
    end

    it "reports the failure once when several directories fail for the same dependency" do
      test_instance.note_security_update_not_possible(dependency, checker, group)

      expect(service).to receive(:record_update_job_error).with(
        error_type: "security_update_not_possible",
        error_details: hash_including("dependency-name": dependency.name),
        dependency: nil
      ).once

      test_instance.report_security_update_failures(nil)
    end

    it "keeps the first diagnosis when a later directory fails differently" do
      test_instance.note_security_update_not_found(dependency, checker, group)

      expect(service).to receive(:record_update_job_error).with(
        error_type: "security_update_not_possible",
        error_details: hash_including("dependency-name": dependency.name),
        dependency: nil
      ).once

      test_instance.report_security_update_failures(nil)
    end

    it "does not report a dependency updated under different casing in another directory" do
      updated = instance_double(Dependabot::Dependency, name: "DEP1")
      dependency_change = instance_double(Dependabot::DependencyChange, updated_dependencies: [updated])

      expect(service).not_to receive(:record_update_job_error)

      test_instance.report_security_update_failures(dependency_change)
    end
  end

  describe "#failed_security_update_dependencies" do
    let(:dependency) { dependencies.first }

    before { allow(job).to receive_messages(security_updates_only?: true) }

    it "excludes a dependency that an earlier update removed from the files" do
      test_instance.removed_dependency_names << dependency.name.downcase

      expect(test_instance.failed_security_update_dependencies(nil)).not_to include(dependency)
    end

    it "keeps a removed dependency that has a diagnosed failure" do
      test_instance.removed_dependency_names << dependency.name.downcase
      test_instance.security_update_failures[dependency.name.downcase] =
        Dependabot::Service::ErrorRecord.new(error_type: "security_update_not_possible", error_details: {})

      expect(test_instance.failed_security_update_dependencies(nil)).to include(dependency)
    end
  end

  describe "#track_removed_dependency" do
    let(:dependency) { dependencies.first }
    let(:removed_names) { Set.new }

    it "records a dependency from the snapshot once the files have changed" do
      test_instance.track_removed_dependency(dependency.name, [dependency], removed_names, changed: true)

      expect(removed_names).to include(dependency.name)
    end

    it "ignores a dependency that was never in the active directory's snapshot" do
      test_instance.track_removed_dependency(dependency.name, [], removed_names, changed: true)

      expect(removed_names).to be_empty
    end

    it "ignores absence before any update has changed the files" do
      test_instance.track_removed_dependency(dependency.name, [dependency], removed_names, changed: false)

      expect(removed_names).to be_empty
    end
  end

  describe "#incoming_file_changes?" do
    let(:snapshot_file) { Dependabot::DependencyFile.new(name: "Gemfile", content: "a", directory: "/") }

    before { allow(dependency_snapshot).to receive(:dependency_files).and_return([snapshot_file]) }

    it "is false when the files match the snapshot" do
      expect(test_instance.incoming_file_changes?([snapshot_file])).to be(false)
    end

    it "is true when an earlier directory deleted a file" do
      expect(test_instance.incoming_file_changes?([])).to be(true)
    end

    it "is true when a shared file was edited by an earlier directory" do
      edited = Dependabot::DependencyFile.new(name: "Gemfile", content: "b", directory: "/")

      expect(test_instance.incoming_file_changes?([edited])).to be(true)
    end
  end

  describe "#collect_absent_group_dependencies" do
    let(:dependency) { dependencies.first }

    it "does not parse when nothing changed" do
      allow(test_instance).to receive(:dependency_file_parser)

      test_instance.collect_absent_group_dependencies([], [dependency], Set.new, changed: false)

      expect(test_instance).not_to have_received(:dependency_file_parser)
    end

    it "records group dependencies missing from the final files" do
      allow(test_instance).to receive(:dependency_file_parser).and_return(
        instance_double(Dependabot::FileParsers::Base, parse: [])
      )
      removed = Set.new

      test_instance.collect_absent_group_dependencies([], [dependency], removed, changed: true)

      expect(removed).to include(dependency.name)
    end
  end

  describe "#commit_deferred_removals" do
    let(:dependency) { dependencies.first }
    let(:file) { Dependabot::DependencyFile.new(name: "Gemfile", content: "edited", directory: "/a") }
    let(:original) { Dependabot::DependencyFile.new(name: "Gemfile", content: "original", directory: "/a") }

    before do
      allow(job.source).to receive(:directories).and_return(["/a"])
      allow(job.source).to receive(:directory=)
      allow(dependency_snapshot).to receive_messages(
        dependency_files: [original],
        dependencies: [dependency],
        all_dependency_files: [original]
      )
      allow(dependency_snapshot).to receive(:current_directory=)
      allow(dependency_snapshot).to receive(:add_handled_dependencies)
      allow(test_instance).to receive_messages(
        working_dependency_files_for: [file],
        dependency_file_parser: instance_double(Dependabot::FileParsers::Base, parse: [])
      )
    end

    it "handles a dependency a later directory removed through a shared file" do
      test_instance.commit_deferred_removals({}, Set.new, [])

      expect(test_instance.removed_dependency_names).to include(dependency.name.downcase)
    end

    it "does not commit a pending removal that the final files reintroduce vulnerably" do
      allow(test_instance).to receive(:dependency_file_parser).and_return(
        instance_double(Dependabot::FileParsers::Base, parse: [dependency])
      )
      allow(job).to receive(:security_advisories_for).and_return([])
      allow(Dependabot::Utils).to receive(:version_class_for_package_manager).and_return(Gem::Version)
      test_instance.instance_variable_set(:@deferred_removals, { "/a" => Set.new([dependency.name]) })

      test_instance.commit_deferred_removals({}, Set.new, [])

      expect(test_instance.removed_dependency_names).to be_empty
      expect(dependency_snapshot).not_to have_received(:add_handled_dependencies)
    end

    it "commits a pending removal with a case-insensitive name" do
      test_instance.instance_variable_set(:@deferred_removals, { "/a" => Set.new(["DEP1"]) })

      test_instance.commit_deferred_removals({}, Set.new, [])

      expect(test_instance.removed_dependency_names).to include("dep1")
    end

    it "cleans up the workspace even when parsing raises" do
      allow(test_instance).to receive(:dependency_file_parser).and_raise(StandardError, "boom")
      allow(test_instance).to receive(:cleanup_workspace)

      expect { test_instance.commit_deferred_removals({}, Set.new, []) }.to raise_error(StandardError, "boom")
      expect(test_instance).to have_received(:cleanup_workspace)
    end

    it "restores the job directory afterwards" do
      test_instance.commit_deferred_removals({}, Set.new, [])

      expect(job.source).to have_received(:directory=).with(job.source.directory).at_least(:once)
    end
  end

  describe "#record_accepted_removals" do
    let(:dependency) { dependencies.first }
    let(:removed_names) { Set.new([dependency.name]) }

    before { allow(dependency_snapshot).to receive(:add_handled_dependencies) }

    it "commits immediately outside a multi-directory compile" do
      test_instance.record_accepted_removals(removed_names)

      expect(test_instance.removed_dependency_names).to include(dependency.name.downcase)
    end

    it "holds removals back while a multi-directory compile is running" do
      test_instance.instance_variable_set(:@deferred_removals, {})

      test_instance.record_accepted_removals(removed_names)

      expect(test_instance.removed_dependency_names).to be_empty
    end
  end

  describe "#forget_reintroduced_dependencies" do
    let(:dependency) { dependencies.first }
    let(:parser) { instance_double(Dependabot::FileParsers::Base) }
    let(:removed_names) { Set.new([dependency.name]) }
    let(:advisory) { instance_double(Dependabot::SecurityAdvisory) }

    before do
      allow(test_instance).to receive(:dependency_file_parser).and_return(parser)
      allow(job).to receive_messages(package_manager: "bundler", security_advisories_for: [advisory])
      allow(Dependabot::Utils).to receive(:version_class_for_package_manager).and_return(Gem::Version)
      allow(advisory).to receive(:vulnerable?) { |version| version < Gem::Version.new("2.0.0") }
    end

    it "keeps a removal that came back at a version no advisory flags" do
      fixed = Dependabot::Dependency.new(
        name: dependency.name, version: "2.0.0", requirements: [], package_manager: "bundler"
      )
      allow(parser).to receive(:parse).and_return([fixed])

      test_instance.forget_reintroduced_dependencies([], removed_names)

      expect(removed_names).to include(dependency.name)
    end

    it "drops a removal when any locked copy is vulnerable" do
      copies = %w(2.0.0 1.0.0).map do |version|
        Dependabot::Dependency.new(
          name: dependency.name, version: version, requirements: [], package_manager: "bundler"
        )
      end
      mixed = Dependabot::Dependency.new(
        name: dependency.name,
        version: "2.0.0",
        requirements: [],
        package_manager: "bundler",
        metadata: { all_versions: copies }
      )
      allow(parser).to receive(:parse).and_return([mixed])

      test_instance.forget_reintroduced_dependencies([], removed_names)

      expect(removed_names).to be_empty
    end

    it "drops a removal that came back at a vulnerable version" do
      vulnerable = Dependabot::Dependency.new(
        name: dependency.name, version: "1.0.0", requirements: [], package_manager: "bundler"
      )
      allow(parser).to receive(:parse).and_return([vulnerable])

      test_instance.forget_reintroduced_dependencies([], removed_names)

      expect(removed_names).to be_empty
    end

    it "keeps a dependency that is still absent from the final files" do
      allow(parser).to receive(:parse).and_return([])

      test_instance.forget_reintroduced_dependencies([], removed_names)

      expect(removed_names).to include(dependency.name)
    end
  end

  describe "compile_all_dependency_changes_for" do
    let(:group_notices) { [] }

    before do
      # Stub all the complex methods that would be called during the method
      allow(test_instance).to receive_messages(
        compile_updates_for: [],
        skip_dependency?: false,
        deduce_updated_dependency: nil,
        store_changes: nil,
        record_warning_notices: nil
      )
      allow(Dependabot::Updater::DependencyGroupChangeBatch).to receive(:new).and_return(
        instance_double(
          Dependabot::Updater::DependencyGroupChangeBatch,
          current_dependency_files: dependency_files,
          updated_dependencies: [],
          updated_dependency_files: dependency_files,
          notices: group_notices,
          add_updated_dependency: nil,
          merge: nil
        )
      )
      allow(Dependabot::DependencyChange).to receive(:new).and_return(
        instance_double(Dependabot::DependencyChange, all_have_previous_version?: true)
      )
    end

    context "when dependency changes generate notices" do
      let(:notice) do
        Dependabot::Notice.new(
          mode: Dependabot::Notice::NoticeMode::WARN,
          type: "cooldown_date_unavailable",
          package_manager_name: "bundler",
          description: "Cooldown was not applied.",
          show_in_pr: true,
          show_alert: false
        )
      end
      let(:group_notices) { [notice] }

      it "passes the notices to the grouped dependency change" do
        allow(Dependabot::DependencyChange).to receive(:new)
          .and_return(instance_double(Dependabot::DependencyChange, all_have_previous_version?: true))

        test_instance.compile_all_dependency_changes_for(group)

        expect(Dependabot::DependencyChange).to have_received(:new)
          .with(hash_including(notices: [notice]))
      end
    end

    context "when a grouped fail-closed check marks a reparsed dependency" do
      let(:original_dependency) do
        Dependabot::Dependency.new(
          name: "dep1",
          version: "1.0.0",
          requirements: [],
          package_manager: "bundler"
        )
      end
      let(:reparsed_dependency) do
        Dependabot::Dependency.new(
          name: "dep1",
          version: "1.0.0",
          requirements: [],
          package_manager: "bundler"
        )
      end
      let(:dependencies) { [original_dependency] }
      let(:group_dependencies) { [original_dependency] }
      let(:checker) do
        instance_double(
          Dependabot::UpdateCheckers::Base,
          dependency: reparsed_dependency,
          up_to_date?: true
        )
      end

      before do
        allow(test_instance).to receive(:compile_updates_for).and_call_original
        allow(test_instance).to receive_messages(
          update_checker_for: checker,
          raise_on_ignored?: false,
          log_checking_for_update: nil,
          record_blocked_version_ignored: nil,
          all_versions_ignored?: false,
          semver_rules_allow_grouping?: true,
          log_up_to_date: nil,
          note_security_update_not_found: nil
        )
        allow(test_instance).to receive(:dependency_file_parser).and_return(
          instance_double(Dependabot::FileParsers::Base, parse: [reparsed_dependency])
        )
        allow(checker).to receive(:up_to_date?) do
          Dependabot::UpdateCheckers::CooldownCalculation.mark_cooldown_date_unavailable(
            reparsed_dependency,
            cooldown_days: 1
          )
          true
        end
      end

      it "propagates the marker to the dependency snapshot" do
        test_instance.compile_all_dependency_changes_for(group)

        expect(Dependabot::UpdateCheckers::CooldownCalculation.cooldown_date_unavailable?(original_dependency))
          .to be(true)
      end

      it "adds the warning to the final grouped dependency change" do
        test_instance.compile_all_dependency_changes_for(group)

        expect(Dependabot::DependencyChange).to have_received(:new) do |notices:, **|
          expect(notices.map(&:type)).to include("cooldown_date_unavailable")
        end
      end
    end

    context "when an earlier update removes a group dependency" do
      let(:removed_dependency) do
        Dependabot::Dependency.new(name: "dep1", version: "1.0.0", requirements: [], package_manager: "bundler")
      end
      let(:dependencies) { [removed_dependency] }
      let(:group_dependencies) { [removed_dependency] }

      before do
        allow(test_instance).to receive(:dependency_file_parser).and_return(
          instance_double(Dependabot::FileParsers::Base, parse: [])
        )
      end

      it "records the removal once the aggregate change is accepted" do
        test_instance.compile_all_dependency_changes_for(group)

        expect(test_instance.removed_dependency_names).to include("dep1")
      end

      it "marks the accepted removal as handled so the ungrouped pass skips it" do
        allow(dependency_snapshot).to receive(:add_handled_dependencies)

        test_instance.compile_all_dependency_changes_for(group)

        expect(dependency_snapshot).to have_received(:add_handled_dependencies).with("dep1")
      end

      it "records a removal of a shared file edited by an earlier directory" do
        edited = Dependabot::DependencyFile.new(name: "Gemfile", content: "edited", directory: "/")
        original = Dependabot::DependencyFile.new(name: "Gemfile", content: "original", directory: "/")
        allow(dependency_snapshot).to receive(:dependency_files).and_return([original])
        allow(Dependabot::Updater::DependencyGroupChangeBatch).to receive(:new).and_call_original

        test_instance.compile_all_dependency_changes_for(group, dependency_files: [edited])

        expect(test_instance.removed_dependency_names).to include("dep1")
      end

      it "records a group dependency skipped earlier that a later update removed" do
        edited = Dependabot::DependencyFile.new(name: "Gemfile", content: "edited", directory: "/")
        original = Dependabot::DependencyFile.new(name: "Gemfile", content: "original", directory: "/")
        allow(dependency_snapshot).to receive(:dependency_files).and_return([original])
        allow(test_instance).to receive(:skip_dependency?).and_return(true)

        test_instance.compile_all_dependency_changes_for(group, dependency_files: [edited])

        expect(test_instance.removed_dependency_names).to include("dep1")
      end

      it "leaves reconciliation to the final pass while directories are deferred" do
        edited = Dependabot::DependencyFile.new(name: "Gemfile", content: "edited", directory: "/")
        original = Dependabot::DependencyFile.new(name: "Gemfile", content: "original", directory: "/")
        allow(dependency_snapshot).to receive(:dependency_files).and_return([original])
        allow(test_instance).to receive(:forget_reintroduced_dependencies)
        test_instance.instance_variable_set(:@deferred_removals, {})

        test_instance.compile_all_dependency_changes_for(group, dependency_files: [edited])

        expect(test_instance).not_to have_received(:forget_reintroduced_dependencies)
        expect(test_instance.instance_variable_get(:@deferred_removals).values).to eq([Set.new(["dep1"])])
      end

      it "discards the removal when the aggregate change is rejected" do
        allow(Dependabot::DependencyChange).to receive(:new).and_return(
          instance_double(Dependabot::DependencyChange, all_have_previous_version?: false)
        )
        allow(test_instance).to receive(:log_missing_previous_version)

        test_instance.compile_all_dependency_changes_for(group)

        expect(test_instance.removed_dependency_names).to be_empty
      end
    end

    context "when checking job dependencies" do
      context "when no job dependency is present in the dependency snapshot" do
        let(:job_dependencies) { %w(missing_dep other_missing_dep) }

        it "records missing dependency error for non-PR updates" do
          expect(error_handler).to receive(:handle_job_error) do |error:|
            expect(error).to be_a(Dependabot::DependencyNotFound)
            expect(error.message).to include("missing_dep")
          end

          test_instance.report_missing_job_dependencies
        end

        it "is not reported while compiling an individual directory" do
          expect(error_handler).not_to receive(:handle_job_error)

          test_instance.compile_all_dependency_changes_for(group)
        end

        context "when updating a pull request" do
          before do
            allow(job).to receive(:updating_a_pull_request?).and_return(true)
          end

          it "does not record missing dependency error" do
            expect(error_handler).not_to receive(:handle_job_error)

            test_instance.report_missing_job_dependencies
          end
        end
      end

      context "when only some job dependencies are missing" do
        let(:job_dependencies) { %w(dep1 missing_dep) }

        it "does not fail the job, since it still has something to update" do
          expect(error_handler).not_to receive(:handle_job_error)

          test_instance.report_missing_job_dependencies
        end
      end

      context "when all job dependencies are present" do
        let(:job_dependencies) { ["dep1"] }

        it "does not record any missing dependency error" do
          expect(error_handler).not_to receive(:handle_job_error)

          test_instance.report_missing_job_dependencies
        end
      end

      context "when a job dependency is present in another directory" do
        let(:job_dependencies) { %w(dep1 dep3) }
        let(:all_dependencies) do
          dependencies + [instance_double(Dependabot::Dependency, name: "dep3")]
        end

        it "does not record a missing dependency error" do
          expect(error_handler).not_to receive(:handle_job_error)

          test_instance.compile_all_dependency_changes_for(group)
        end
      end
    end
  end

  describe "workspace handling in compile_all_dependency_changes_for" do
    let(:clone_job) { true }
    let(:repo_contents_path) { "/tmp/dependabot/repo" }
    let(:source_directory) { "/services/api/../api" }

    before do
      allow(test_instance).to receive(:prepare_workspace).and_call_original
      allow(test_instance).to receive(:cleanup_workspace).and_call_original
      allow(test_instance).to receive_messages(
        compile_updates_for: [],
        skip_dependency?: false,
        deduce_updated_dependency: nil,
        store_changes: nil,
        record_warning_notices: nil
      )
      allow(Dependabot::Updater::DependencyGroupChangeBatch).to receive(:new).and_return(
        instance_double(
          Dependabot::Updater::DependencyGroupChangeBatch,
          current_dependency_files: dependency_files,
          updated_dependencies: [],
          updated_dependency_files: dependency_files,
          notices: [],
          add_updated_dependency: nil,
          merge: nil
        )
      )
      allow(Dependabot::DependencyChange).to receive(:new).and_return(
        instance_double(Dependabot::DependencyChange, all_have_previous_version?: true)
      )
      allow(Dependabot::Workspace).to receive(:setup)
      allow(Dependabot::Workspace).to receive(:cleanup!)
    end

    it "sets up and cleans up the workspace for clone jobs" do
      workspace_file = Dependabot::DependencyFile.new(name: "Gemfile", content: "source 'https://rubygems.org'")
      allow(test_instance).to receive(:materialize_workspace_files)

      test_instance.compile_all_dependency_changes_for(group, workspace_files: [workspace_file])

      expect(Dependabot::Workspace).to have_received(:setup).with(
        repo_contents_path: repo_contents_path,
        directory: Pathname.new(source_directory).cleanpath
      )
      expect(test_instance).to have_received(:materialize_workspace_files).with([workspace_file])
      expect(Dependabot::Workspace).to have_received(:cleanup!).once
    end

    context "with a cumulative submodule update" do
      let(:repo_contents_path) { build_tmp_repo("maven_multi_directory_group", path: "") }
      let(:submodule_file) do
        Dependabot::DependencyFile.new(
          name: "submodule",
          content: "1111111111111111111111111111111111111111",
          type: "submodule",
          mode: Dependabot::DependencyFile::Mode::SUBMODULE
        )
      end
      let(:staged_submodule) { [] }

      before do
        allow(Dependabot::Workspace).to receive(:setup).and_call_original
        allow(Dependabot::Workspace).to receive(:cleanup!).and_call_original
        allow(test_instance).to receive(:dependency_file_parser) do
          staged_submodule << Dependabot::SharedHelpers.run_shell_command(
            ["git", "ls-files", "--stage", "submodule"],
            cwd: repo_contents_path
          )
          instance_double(Dependabot::FileParsers::Base, parse: dependencies)
        end
      end

      after do
        FileUtils.rm_rf(repo_contents_path)
      end

      it "stages the submodule as a gitlink before parsing" do
        test_instance.compile_all_dependency_changes_for(group, workspace_files: [submodule_file])

        expect(staged_submodule.first).to start_with(
          "160000 1111111111111111111111111111111111111111"
        )
      end
    end

    context "with a cumulative file created outside the active directory" do
      let(:repo_contents_path) { build_tmp_repo("maven_multi_directory_group", path: "") }
      let(:source_directory) { "/module-a" }
      let(:created_file) do
        Dependabot::DependencyFile.new(
          name: "created.tf",
          content: "created",
          operation: Dependabot::DependencyFile::Operation::CREATE
        )
      end
      let(:created_path) { File.join(repo_contents_path, "created.tf") }
      let(:materialized_file_seen) { [] }

      before do
        allow(Dependabot::Workspace).to receive(:setup).and_call_original
        allow(Dependabot::Workspace).to receive(:cleanup!).and_call_original
        allow(test_instance).to receive(:dependency_file_parser) do
          materialized_file_seen << File.exist?(created_path)
          instance_double(Dependabot::FileParsers::Base, parse: dependencies)
        end
      end

      after do
        FileUtils.rm_rf(repo_contents_path)
      end

      it "removes the created file after compilation" do
        test_instance.compile_all_dependency_changes_for(group, workspace_files: [created_file])

        expect(materialized_file_seen).to all(be(true))
        expect(File).not_to exist(created_path)
      end
    end
  end

  describe "cross-directory removal and reintroduction through a shared file" do
    let(:parent) do
      Dependabot::Dependency.new(name: "parent", version: "1.0.0", requirements: [], package_manager: "bundler")
    end
    let(:child) do
      Dependabot::Dependency.new(name: "dep1", version: "1.0.0", requirements: [], package_manager: "bundler")
    end
    let(:dependencies) { [parent, child] }
    let(:group_dependencies) { [parent, child] }
    let(:shared_file) { Dependabot::DependencyFile.new(name: "shared.lock", content: "v1", directory: "/") }
    let(:advisory) { instance_double(Dependabot::SecurityAdvisory) }
    let(:security_advisories) { [advisory] }
    let(:updates) { %w(removed reintroduced).each_with_index.to_h { |content, i| [i, content] } }
    let(:next_content) { updates.values.each }

    before do
      allow(source).to receive(:directories).and_return(%w(/a /b))
      allow(source).to receive(:directory=) { |dir| allow(source).to receive(:directory).and_return(dir) }
      allow(dependency_snapshot).to receive_messages(
        all_dependency_files: [shared_file],
        dependency_files: [shared_file],
        dependencies: dependencies,
        handled_dependencies: Set.new
      )
      allow(dependency_snapshot).to receive(:current_directory=)
      allow(advisory).to receive(:vulnerable?).and_return(true)
      allow(job).to receive(:security_updates_only?).and_return(true)
      allow(Dependabot::Utils).to receive(:version_class_for_package_manager).and_return(Gem::Version)
      allow(test_instance).to receive(:dependency_file_parser) do |files|
        content = files.find { |f| f.name.end_with?("shared.lock") }&.content
        parsed = content&.start_with?("removed") ? [parent] : [parent, child]
        instance_double(Dependabot::FileParsers::Base, parse: parsed)
      end
      allow(test_instance).to receive(:compile_updates_for) do |dependency, _files, _group|
        next [] unless dependency.name == "parent"

        [Dependabot::Dependency.new(
          name: "parent",
          version: "2.0.0",
          previous_version: "1.0.0",
          requirements: [],
          previous_requirements: [],
          package_manager: "bundler"
        )]
      end
      allow(test_instance).to receive(:create_change_for) do |lead, _updated, _files, _group|
        file = Dependabot::DependencyFile.new(
          name: "shared.lock",
          content: next_content.next,
          directory: "/",
          operation: Dependabot::DependencyFile::Operation::UPDATE
        )
        Dependabot::DependencyChange.new(
          job: job, updated_dependencies: [lead], updated_dependency_files: [file]
        )
      end
    end

    context "when the second directory reintroduces the vulnerable dependency" do
      it "neither records the removal nor marks the dependency handled, so it is still reported" do
        change = test_instance.compile_all_dependency_changes_for_directories(group)

        expect(test_instance.removed_dependency_names).to be_empty
        expect(dependency_snapshot).not_to have_received(:add_handled_dependencies).with("dep1")
        expect(test_instance.failed_security_update_dependencies(change).map(&:name)).to include("dep1")
      end
    end

    context "when the second directory keeps the dependency removed" do
      let(:updates) { { 0 => "removed", 1 => "removed-again" } }

      it "records the removal, marks it handled and does not report it" do
        change = test_instance.compile_all_dependency_changes_for_directories(group)

        expect(test_instance.removed_dependency_names).to include("dep1")
        expect(dependency_snapshot).to have_received(:add_handled_dependencies).with("dep1").at_least(:once)
        expect(test_instance.failed_security_update_dependencies(change).map(&:name)).not_to include("dep1")
      end
    end
  end

  describe "#compile_all_dependency_changes_for_directories" do
    let(:original_file) do
      Dependabot::DependencyFile.new(name: "Gemfile", content: "original")
    end
    let(:raw_updated_file) do
      Dependabot::DependencyFile.new(
        name: "Gemfile",
        content: "updated",
        operation: Dependabot::DependencyFile::Operation::CREATE
      )
    end
    let(:first_change) do
      instance_double(
        Dependabot::DependencyChange,
        updated_dependencies: [],
        updated_dependency_files: [raw_updated_file]
      )
    end

    before do
      allow(source).to receive(:directories).and_return(["/dir1", "/dir2"])
      allow(source).to receive(:directory=)
      allow(dependency_snapshot).to receive_messages(
        all_dependency_files: [original_file],
        dependency_files: [original_file]
      )
      allow(dependency_snapshot).to receive(:current_directory=)
      allow(test_instance).to receive(:compile_all_dependency_changes_for).and_return(first_change, nil)
    end

    it "uses the normalized file set when only one directory changes" do
      change = test_instance.compile_all_dependency_changes_for_directories(group)

      expect(change.updated_dependency_files.first).to have_attributes(
        content: "updated",
        operation: Dependabot::DependencyFile::Operation::UPDATE
      )
    end
  end

  describe "#compile_updates_for blocked versions ignored metric" do
    let(:dependency) { dependencies.first }
    let(:group) do
      instance_double(
        Dependabot::DependencyGroup,
        name: "test-group",
        dependencies: [dependency],
        group_by_dependency_name?: false
      )
    end

    let(:metrics_service) do
      instance_double(Dependabot::Service, record_update_job_error: nil, increment_metric: nil)
    end

    before do
      allow(test_instance).to receive_messages(
        update_checker_for: checker,
        raise_on_ignored?: false,
        log_checking_for_update: nil,
        all_versions_ignored?: false,
        semver_rules_allow_grouping?: true,
        log_up_to_date: nil,
        requirements_to_unlock: [],
        log_requirements_for_update: nil,
        service: metrics_service
      )
      allow(job).to receive(:package_manager).and_return("bundler")
      allow(checker).to receive(:up_to_date?).and_return(true)
    end

    context "when the dependency has an active GitHub Security block" do
      before do
        allow(job).to receive(:blocked_versions_for?).with(dependency).and_return(true)
      end

      it "increments the ignored metric tagged with group_update" do
        test_instance.compile_updates_for(dependency, dependency_files, group)

        expect(metrics_service).to have_received(:increment_metric).with(
          "blocked_versions.ignored",
          tags: {
            operation: "group_update",
            package_manager: "bundler"
          }
        )
      end
    end

    context "when the dependency only has user ignore rules (no block)" do
      before do
        allow(job).to receive(:blocked_versions_for?).with(dependency).and_return(false)
      end

      it "does not increment the ignored metric" do
        test_instance.compile_updates_for(dependency, dependency_files, group)

        expect(metrics_service).not_to have_received(:increment_metric).with(
          "blocked_versions.ignored",
          tags: anything
        )
      end
    end
  end

  describe "#compile_updates_for group-by-name handled deps" do
    let(:dependency) { dependencies.first }

    before do
      allow(test_instance).to receive_messages(
        update_checker_for: checker,
        raise_on_ignored?: false,
        log_checking_for_update: nil,
        all_versions_ignored?: false,
        semver_rules_allow_grouping?: true,
        log_up_to_date: nil,
        requirements_to_unlock: [],
        log_requirements_for_update: nil
      )
      allow(checker).to receive(:up_to_date?).and_return(false)
    end

    context "when semver rules reject grouping for a group-by-name subgroup" do
      let(:group) do
        Dependabot::DependencyGroup.new(
          name: "per-dependency/dep1",
          rules: {
            "patterns" => ["dep1"],
            "group-by" => "dependency-name",
            "update-types" => %w(minor patch)
          }
        )
      end

      before do
        allow(test_instance).to receive(:semver_rules_allow_grouping?).and_return(false)
      end

      it "marks the dependency as handled" do
        test_instance.compile_updates_for(dependency, dependency_files, group)
        expect(dependency_snapshot).to have_received(:add_handled_dependencies).with(dependency.name)
      end

      it "returns an empty array" do
        result = test_instance.compile_updates_for(dependency, dependency_files, group)
        expect(result).to eq([])
      end
    end

    context "when all versions are ignored for a group-by-name subgroup" do
      let(:group) do
        Dependabot::DependencyGroup.new(
          name: "per-dependency/dep1",
          rules: {
            "patterns" => ["dep1"],
            "group-by" => "dependency-name",
            "update-types" => %w(minor patch)
          }
        )
      end

      before do
        allow(test_instance).to receive(:all_versions_ignored?).and_return(true)
        allow(test_instance).to receive(:note_security_update_ignored)
      end

      it "marks the dependency as handled" do
        test_instance.compile_updates_for(dependency, dependency_files, group)
        expect(dependency_snapshot).to have_received(:add_handled_dependencies).with(dependency.name)
      end

      it "returns an empty array" do
        result = test_instance.compile_updates_for(dependency, dependency_files, group)
        expect(result).to eq([])
      end
    end

    context "when semver rules reject grouping for a regular group (not group-by-name)" do
      let(:group) do
        Dependabot::DependencyGroup.new(
          name: "minor-and-patch",
          rules: {
            "patterns" => ["dep1"],
            "update-types" => %w(minor patch)
          }
        )
      end

      before do
        allow(test_instance).to receive(:semver_rules_allow_grouping?).and_return(false)
      end

      it "does NOT mark the dependency as handled" do
        test_instance.compile_updates_for(dependency, dependency_files, group)
        expect(dependency_snapshot).not_to have_received(:add_handled_dependencies)
      end

      it "returns an empty array" do
        result = test_instance.compile_updates_for(dependency, dependency_files, group)
        expect(result).to eq([])
      end
    end

    context "when all versions are ignored for a regular group (not group-by-name)" do
      let(:group) do
        Dependabot::DependencyGroup.new(
          name: "minor-and-patch",
          rules: {
            "patterns" => ["dep1"],
            "update-types" => %w(minor patch)
          }
        )
      end

      before do
        allow(test_instance).to receive(:all_versions_ignored?).and_return(true)
        allow(test_instance).to receive(:note_security_update_ignored)
      end

      it "does NOT mark the dependency as handled" do
        test_instance.compile_updates_for(dependency, dependency_files, group)
        expect(dependency_snapshot).not_to have_received(:add_handled_dependencies)
      end

      it "returns an empty array" do
        result = test_instance.compile_updates_for(dependency, dependency_files, group)
        expect(result).to eq([])
      end
    end
  end

  describe "#compile_updates_for when all versions are ignored only on the resolvable path" do
    # Regression: the cooldown fallback can let the `all_versions_ignored?` guard pass
    # (latest_version returns the current version) while `can_update?` still raises
    # AllVersionsIgnored via a different finder. For a non-security job that raise must
    # be treated as "no update possible" and skip the dependency, not escape the run.
    let(:dependency) { dependencies.first }
    let(:group) do
      instance_double(
        Dependabot::DependencyGroup,
        name: "test-group",
        dependencies: [dependency],
        group_by_dependency_name?: false
      )
    end

    before do
      allow(test_instance).to receive_messages(
        update_checker_for: checker,
        raise_on_ignored?: false,
        log_checking_for_update: nil,
        all_versions_ignored?: false,
        semver_rules_allow_grouping?: true,
        log_requirements_for_update: nil,
        note_security_update_not_possible: nil
      )
      allow(checker).to receive(:requirements_unlocked_or_can_be?).and_return(true)
      allow(checker).to receive(:can_update?).and_raise(Dependabot::AllVersionsIgnored)
    end

    context "when the job is not a security update" do
      before { allow(job).to receive(:security_updates_only?).and_return(false) }

      it "skips the dependency without raising or reporting a dependency error" do
        expect(error_handler).not_to receive(:handle_dependency_error)

        result = nil
        expect { result = test_instance.compile_updates_for(dependency, dependency_files, group) }
          .not_to raise_error
        expect(result).to eq([])
      end
    end

    context "when the job is a security update" do
      before { allow(job).to receive(:security_updates_only?).and_return(true) }

      it "still surfaces AllVersionsIgnored via the error handler" do
        allow(error_handler).to receive(:handle_dependency_error)

        test_instance.compile_updates_for(dependency, dependency_files, group)

        expect(error_handler).to have_received(:handle_dependency_error)
          .with(hash_including(error: an_instance_of(Dependabot::AllVersionsIgnored)))
      end
    end
  end

  describe "#compile_updates_for when all versions are ignored only on updated_dependencies" do
    # Regression: even after `can_update?` succeeds, `updated_dependencies` can still raise
    # AllVersionsIgnored when the resolvable-version finder ignores every candidate. For a
    # non-security job that raise must skip the dependency, not escape to the run.
    let(:dependency) { dependencies.first }
    let(:group) do
      instance_double(
        Dependabot::DependencyGroup,
        name: "test-group",
        dependencies: [dependency],
        group_by_dependency_name?: false
      )
    end

    before do
      allow(test_instance).to receive_messages(
        update_checker_for: checker,
        raise_on_ignored?: false,
        log_checking_for_update: nil,
        all_versions_ignored?: false,
        semver_rules_allow_grouping?: true,
        log_requirements_for_update: nil,
        note_security_update_not_possible: nil
      )
      allow(checker).to receive_messages(requirements_unlocked_or_can_be?: true, can_update?: true)
      allow(checker).to receive(:updated_dependencies).and_raise(Dependabot::AllVersionsIgnored)
    end

    context "when the job is not a security update" do
      before { allow(job).to receive(:security_updates_only?).and_return(false) }

      it "skips the dependency without raising or reporting a dependency error" do
        expect(error_handler).not_to receive(:handle_dependency_error)

        result = nil
        expect { result = test_instance.compile_updates_for(dependency, dependency_files, group) }
          .not_to raise_error
        expect(result).to eq([])
      end
    end

    context "when the job is a security update" do
      before { allow(job).to receive(:security_updates_only?).and_return(true) }

      it "still surfaces AllVersionsIgnored via the error handler" do
        allow(error_handler).to receive(:handle_dependency_error)

        test_instance.compile_updates_for(dependency, dependency_files, group)

        expect(error_handler).to have_received(:handle_dependency_error)
          .with(hash_including(error: an_instance_of(Dependabot::AllVersionsIgnored)))
      end
    end
  end

  describe "#compile_updates_for with multiple locked Cargo versions" do
    let(:dependency) do
      Dependabot::Dependency.new(
        name: "getrandom",
        version: "0.2.17",
        requirements: [],
        package_manager: "cargo",
        metadata: { all_versions: locked_versions }
      )
    end
    let(:dependencies) { [dependency] }
    let(:locked_versions) do
      ["0.2.17", "0.4.2"].map do |version|
        Dependabot::Dependency.new(
          name: "getrandom",
          version: version,
          requirements: [],
          package_manager: "cargo",
          metadata: { cargo_package_source: "registry+https://github.com/rust-lang/crates.io-index" }
        )
      end
    end
    let(:updated_dependency) do
      Dependabot::Dependency.new(
        name: "getrandom",
        version: "0.4.3",
        previous_version: "0.4.2",
        requirements: [],
        previous_requirements: [],
        package_manager: "cargo"
      )
    end
    let(:group) do
      Dependabot::DependencyGroup.new(
        name: "patch-updates",
        rules: {
          "patterns" => ["getrandom"],
          "update-types" => ["patch"]
        }
      )
    end

    # The updater CI image only carries one ecosystem gem, so dependabot-cargo
    # cannot be loaded here. Resolve the version class generically and supply
    # a minimal Cargo::Version.update_type with cargo's pre-1.0 rule (a 0.x
    # minor bump is a major update) so the classification stays meaningful.
    let(:cargo_version_stub) do
      Class.new do
        def self.update_type(from_version, to_version)
          from = Gem::Version.new(from_version.to_s).segments
          to = Gem::Version.new(to_version.to_s).segments
          return "major" if from[0] != to[0] || (from[0].to_i.zero? && from[1] != to[1])
          return "minor" if from[1] != to[1]

          "patch"
        end
      end
    end

    before do
      stub_const("Dependabot::Cargo::Version", cargo_version_stub)
      allow(Dependabot::Utils).to receive(:version_class_for_package_manager).and_return(Dependabot::Version)
      allow(job).to receive(:package_manager).and_return("cargo")
      allow(test_instance).to receive_messages(
        update_checker_for: checker,
        raise_on_ignored?: false,
        log_checking_for_update: nil,
        all_versions_ignored?: false,
        log_up_to_date: nil,
        requirements_to_unlock: :own,
        log_requirements_for_update: nil
      )
      allow(checker).to receive_messages(
        up_to_date?: false,
        updated_dependencies: [updated_dependency]
      )
    end

    it "classifies the actionable locked line instead of the collapsed dependency" do
      expect(test_instance.compile_updates_for(dependency, dependency_files, group))
        .to eq([updated_dependency])
    end
  end

  describe "security error reporting in compile_updates_for" do
    let(:dependency) { dependencies.first }

    before do
      # Stub the complex methods that would be called
      allow(test_instance).to receive_messages(
        update_checker_for: checker,
        raise_on_ignored?: false,
        log_checking_for_update: nil,
        all_versions_ignored?: false,
        semver_rules_allow_grouping?: true,
        log_up_to_date: nil,
        requirements_to_unlock: [],
        log_requirements_for_update: nil
      )
      allow(checker).to receive(:up_to_date?).and_return(false)
    end

    context "when checking security updates" do
      context "when an update is not possible for a version outside the advisory range" do
        let(:dependency) do
          Dependabot::Dependency.new(
            name: "dep1",
            version: "2.0.0",
            requirements: [],
            package_manager: "dummy"
          )
        end
        let(:checker) { advisory_checker }
        let(:security_advisories) { [security_advisory] }

        before do
          allow(test_instance).to receive(:requirements_to_unlock).and_return(:update_not_possible)
        end

        it "does not record a security update failure" do
          expect(service).not_to receive(:record_update_job_error)

          test_instance.compile_updates_for(dependency, dependency_files, group)
          test_instance.report_security_update_failure(dependency.name)
        end
      end

      context "when a secondary installed version is within the advisory range" do
        let(:multi_version_checker_class) do
          Class.new(Dependabot::UpdateCheckers::Base) do
            def vulnerable?
              dependency.all_versions.any? do |version|
                security_advisories.any? { |advisory| advisory.affects_version?(version) }
              end
            end
          end
        end
        let(:locked_versions) do
          %w(2.0.0 1.0.0).map do |version|
            Dependabot::Dependency.new(
              name: "dep1",
              version: version,
              requirements: [],
              package_manager: "dummy"
            )
          end
        end
        let(:dependency) do
          Dependabot::Dependency.new(
            name: "dep1",
            version: "2.0.0",
            requirements: [],
            package_manager: "dummy",
            metadata: { all_versions: locked_versions }
          )
        end
        let(:checker) do
          multi_version_checker_class.new(
            dependency: dependency,
            dependency_files: [],
            credentials: [],
            security_advisories: security_advisories
          )
        end
        let(:security_advisories) { [security_advisory] }

        before do
          allow(test_instance).to receive(:requirements_to_unlock).and_return(:update_not_possible)
          allow(checker).to receive_messages(
            lowest_resolvable_security_fix_version: nil,
            lowest_security_fix_version: Gem::Version.new("1.0.1")
          )
        end

        it "records a security update failure for the vulnerable version" do
          expect(service).to receive(:record_update_job_error).with(
            error_type: "security_update_not_possible",
            error_details: hash_including("dependency-name": dependency.name),
            dependency: nil
          )

          test_instance.compile_updates_for(dependency, dependency_files, group)
          test_instance.report_security_update_failure(dependency.name)
        end
      end

      context "when all versions are ignored and dependency has security advisories" do
        before do
          allow(test_instance).to receive(:all_versions_ignored?).and_return(true)
          allow(job).to receive(:security_advisories_for).with(dependency).and_return([{ "id" => "advisory-1" }])
        end

        it "calls note_security_update_ignored" do
          expect(test_instance).to receive(:note_security_update_ignored)
            .with(dependency, checker, group)

          test_instance.compile_updates_for(dependency, dependency_files, group)
        end
      end

      context "when dependency is up to date and has security advisories" do
        before do
          allow(checker).to receive(:up_to_date?).and_return(true)
          allow(job).to receive(:security_advisories_for).with(dependency).and_return([{ "id" => "advisory-1" }])
        end

        it "calls note_security_update_not_found" do
          expect(test_instance).to receive(:note_security_update_not_found)
            .with(dependency, checker, group)

          test_instance.compile_updates_for(dependency, dependency_files, group)
        end
      end
    end
  end

  describe "#create_change_for" do
    let(:no_change_error_class) { Class.new(StandardError) }
    let(:lead_dependency) do
      instance_double(Dependabot::Dependency, name: "dep1", version: "1.0.1")
    end
    let(:updated_dependencies) { [lead_dependency] }

    it "handles file updater no-change errors from DependencyChangeBuilder" do
      no_change_error = no_change_error_class.new("No files were updated!")

      allow(Dependabot::DependencyChangeBuilder).to receive(:create_from).and_raise(no_change_error)

      expect(error_handler).to receive(:handle_dependency_error).with(
        error: no_change_error,
        dependency: lead_dependency,
        dependency_group: group
      )

      result = test_instance.send(
        :create_change_for,
        lead_dependency,
        updated_dependencies,
        dependency_files,
        group
      )

      expect(result).to be(false)
    end
  end

  describe "#skip_dependency? directory filtering" do
    let(:group) do
      instance_double(
        Dependabot::DependencyGroup,
        name: "test-group",
        dependencies: group_dependencies,
        group_by_dependency_name?: false
      )
    end

    context "when dependency directory matches the job source directory" do
      let(:source_directory) { "/app" }
      let(:dependency) do
        instance_double(Dependabot::Dependency, name: "dep1", version: "1.0.0", directory: "/app")
      end

      it "does not skip the dependency" do
        result = test_instance.send(:skip_dependency?, dependency, group)
        expect(result).to be(false)
      end
    end

    context "when dependency directory differs from the job source directory" do
      let(:source_directory) { "/app" }
      let(:dependency) do
        instance_double(Dependabot::Dependency, name: "dep1", version: "1.0.0", directory: "/other")
      end

      it "skips the dependency" do
        result = test_instance.send(:skip_dependency?, dependency, group)
        expect(result).to be(true)
      end
    end

    context "when dependency directory is nil" do
      let(:source_directory) { "/app" }
      let(:dependency) do
        instance_double(Dependabot::Dependency, name: "dep1", version: "1.0.0", directory: nil)
      end

      it "does not skip the dependency (nil is treated as belonging to any directory)" do
        result = test_instance.send(:skip_dependency?, dependency, group)
        expect(result).to be(false)
      end
    end

    context "when both dependency directory and source directory are '/'" do
      let(:source_directory) { "/" }
      let(:dependency) do
        instance_double(Dependabot::Dependency, name: "dep1", version: "1.0.0", directory: "/")
      end

      it "does not skip the dependency" do
        result = test_instance.send(:skip_dependency?, dependency, group)
        expect(result).to be(false)
      end
    end

    context "when directories are equivalent but differ in formatting" do
      let(:source_directory) { "/app/./config/../config" }
      let(:dependency) do
        instance_double(Dependabot::Dependency, name: "dep1", version: "1.0.0", directory: "/app/config")
      end

      it "does not skip the dependency (paths are normalized before comparison)" do
        result = test_instance.send(:skip_dependency?, dependency, group)
        expect(result).to be(false)
      end
    end
  end

  describe "#skip_dependency? single-directory regression" do
    let(:source_directory) { "/" }
    let(:group) do
      instance_double(
        Dependabot::DependencyGroup,
        name: "test-group",
        dependencies: group_dependencies,
        group_by_dependency_name?: false
      )
    end

    context "when dependency directory matches root '/'" do
      let(:dependency) do
        instance_double(Dependabot::Dependency, name: "dep1", version: "1.0.0", directory: "/")
      end

      it "does not skip the dependency" do
        result = test_instance.send(:skip_dependency?, dependency, group)
        expect(result).to be(false)
      end
    end

    context "when dependency directory is nil in single-directory job" do
      let(:dependency) do
        instance_double(Dependabot::Dependency, name: "dep1", version: "1.0.0", directory: nil)
      end

      it "does not skip the dependency" do
        result = test_instance.send(:skip_dependency?, dependency, group)
        expect(result).to be(false)
      end
    end

    context "when dependency has already been handled" do
      let(:dependency) do
        instance_double(Dependabot::Dependency, name: "dep1", version: "1.0.0", directory: "/")
      end

      before do
        allow(dependency_snapshot).to receive(:handled_dependencies).and_return(Set.new(["dep1"]))
      end

      it "skips the dependency" do
        result = test_instance.send(:skip_dependency?, dependency, group)
        expect(result).to be(true)
      end
    end

    context "when dependency has been handled but is a group refresh" do
      let(:dependency) do
        instance_double(Dependabot::Dependency, name: "dep1", version: "1.0.0", directory: "/")
      end

      before do
        allow(dependency_snapshot).to receive(:handled_dependencies).and_return(Set.new(["dep1"]))
        allow(job).to receive(:dependency_group_to_refresh).and_return("test-group")
      end

      it "does not skip the dependency" do
        result = test_instance.send(:skip_dependency?, dependency, group)
        expect(result).to be(false)
      end
    end
  end
end
