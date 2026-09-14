# typed: false
# frozen_string_literal: true

require "spec_helper"
require "support/dummy_pkg_helpers"
require "dependabot/dependency_change"
require "dependabot/dependency_snapshot"
require "dependabot/service"
require "dependabot/updater/error_handler"
require "dependabot/updater/operations/create_group_update_pull_request"
require "dependabot/updater/group_dependency_selector"
require "dependabot/update_checkers"
require "dependabot/update_checkers/base"
require "dependabot/file_parsers"
require "dependabot/file_parsers/base"
require "dependabot/file_updaters"
require "dependabot/file_updaters/base"
require "dependabot/maven"

# End-to-end test for multi-directory grouped PR creation.
#
# A terraform monorepo has 3 directories, each with the same 3 providers. On a grouped
# creation job, compile_all_dependency_changes_for is called per directory and the results
# are combined via filter_map. When every directory is filtered out (nothing can update),
# the array is empty and the old T.must(dependency_changes.first) raised
# `TypeError: Passed nil into T.must` (Sentry DELTAFORCE-1K1Y). This exercises the public
# #perform to prove the guard returns nil instead of crashing.
RSpec.describe Dependabot::Updater::Operations::CreateGroupUpdatePullRequest do
  describe "#perform with multi-directory groups" do
    subject(:create_operation) do
      described_class.new(
        service: mock_service,
        job: job,
        dependency_snapshot: dependency_snapshot,
        error_handler: mock_error_handler,
        group: dependency_group
      )
    end

    let(:directories) { ["/dir1", "/dir2", "/dir3"] }
    let(:dep_names) { %w(hashicorp/aws hashicorp/google hashicorp/kubernetes) }

    let(:mock_service) do
      instance_double(
        Dependabot::Service,
        increment_metric: nil,
        record_update_job_error: nil,
        record_update_job_warning: nil,
        record_ecosystem_meta: nil,
        record_cooldown_meta: nil
      )
    end

    let(:mock_error_handler) do
      instance_double(Dependabot::Updater::ErrorHandler, handle_dependency_error: nil)
    end

    let(:dependency_files) do
      directories.map do |dir|
        Dependabot::DependencyFile.new(
          name: "main.tf",
          content: "# terraform config",
          directory: dir
        )
      end
    end

    let(:job) do
      Dependabot::Job.new_update_job(
        job_id: "1234",
        job_definition: {
          "job" => {
            "package-manager" => "terraform",
            "source" => {
              "provider" => "github",
              "repo" => "test/terraform-monorepo",
              "directories" => directories,
              "branch" => nil,
              "api-endpoint" => "https://api.github.com/",
              "hostname" => "github.com"
            },
            "dependencies" => dep_names,
            "existing-pull-requests" => [],
            "existing-group-pull-requests" => [],
            "updating-a-pull-request" => false,
            "lockfile-only" => false,
            "update-subdependencies" => false,
            "ignore-conditions" => [],
            "requirements-update-strategy" => nil,
            "allowed-updates" => [{ "dependency-type" => "direct", "update-type" => "all" }],
            "credentials-metadata" => [{ "type" => "git_source", "host" => "github.com" }],
            "security-advisories" => [],
            "vendor-dependencies" => false,
            "experiments" => { "grouped-updates-prototype" => true },
            "reject-external-code" => false,
            "commit-message-options" => {},
            "security-updates-only" => false,
            "dependency-groups" => [{
              "name" => "all-terraform",
              "rules" => { "patterns" => ["*"] }
            }]
          }
        }
      )
    end

    let(:dependency_snapshot) do
      Dependabot::DependencySnapshot.create_from_job_definition(
        job: job,
        fetched_files: Dependabot::FetchedFiles.new(
          base_commit_sha: "mock-sha",
          dependency_files: dependency_files
        )
      )
    end

    let(:dependency_group) do
      dependency_snapshot.groups.find { |g| g.name == "all-terraform" }
    end

    let(:ecosystem) do
      Dependabot::Ecosystem.new(
        name: "terraform",
        package_manager: DummyPkgHelpers::StubPackageManager.new(
          name: "terraform", version: "1.5.0", supported_versions: %w(1.5 1.6)
        )
      )
    end

    before do
      # Register fake implementations BEFORE dependency_snapshot is created.
      # DependencySnapshot#initialize calls parse_files! which needs these.
      Dependabot::Dependency.register_production_check("terraform", ->(_groups) { true })

      Dependabot::FileParsers.register(
        "terraform",
        Class.new(Dependabot::FileParsers::Base) do
          define_method(:parse) do
            dir = source&.directory || "/"
            %w(hashicorp/aws hashicorp/google hashicorp/kubernetes).map do |name|
              Dependabot::Dependency.new(
                name: name,
                version: "4.0.0",
                requirements: [{
                  file: "main.tf", requirement: "~> 4.0", groups: [],
                  source: { type: "provider", registry_hostname: "registry.terraform.io",
                            module_identifier: name }
                }],
                package_manager: "terraform",
                directory: dir
              )
            end
          end
          define_method(:ecosystem) { nil }
          define_method(:check_required_files) { nil }
        end
      )

      Dependabot::UpdateCheckers.register(
        "terraform",
        Class.new(Dependabot::UpdateCheckers::Base) do
          define_method(:latest_version) { Gem::Version.new("5.0.0") }
          define_method(:latest_resolvable_version) { Gem::Version.new("5.0.0") }
          define_method(:latest_resolvable_version_with_no_unlock) { Gem::Version.new("5.0.0") }
          define_method(:lowest_security_fix_version) { nil }
          define_method(:lowest_resolvable_security_fix_version) { nil }
          define_method(:updated_requirements) do
            dependency.requirements.map { |r| r.merge(requirement: "~> 5.0") }
          end
          define_method(:up_to_date?) { false }
          define_method(:requirements_unlocked_or_can_be?) { true }
          define_method(:can_update?) { |**_kwargs| true }
          define_method(:updated_dependencies) do |**_kwargs|
            [Dependabot::Dependency.new(
              name: dependency.name,
              version: "5.0.0",
              requirements: dependency.requirements.map { |r| r.merge(requirement: "~> 5.0") },
              previous_version: "4.0.0",
              previous_requirements: dependency.requirements,
              package_manager: "terraform",
              directory: dependency.directory
            )]
          end
        end
      )

      Dependabot::FileUpdaters.register(
        "terraform",
        Class.new(Dependabot::FileUpdaters::Base) do
          define_method(:updated_dependency_files) do
            dependency_files.map do |f|
              Dependabot::DependencyFile.new(name: f.name, content: "# updated", directory: f.directory)
            end
          end
          define_method(:check_required_files) { nil }
        end
      )

      Dependabot::Utils.register_version_class("terraform", Dependabot::Version)
      Dependabot::Utils.register_requirement_class("terraform", Dependabot::Requirement)

      Dependabot::Experiments.reset!

      allow(dependency_snapshot).to receive(:ecosystem).and_return(ecosystem)
      allow(job).to receive(:package_manager).and_return("terraform")
    end

    after do
      Dependabot::Experiments.reset!
    end

    it "creates a pull request with exactly 3 updated dependencies per directory" do
      dependency_change = nil
      allow(mock_service).to receive(:create_pull_request) { |change| dependency_change = change }

      create_operation.perform

      expect(dependency_change).not_to be_nil
      expect(dependency_change.updated_dependencies.length).to eq(9)
    end

    context "when directories change shared file lifecycle and metadata" do
      let(:directories) { ["/dir1", "/dir2"] }
      let(:dependency_files) do
        directories.flat_map do |directory|
          [
            Dependabot::DependencyFile.new(name: "main.tf", content: "# terraform config", directory: directory),
            Dependabot::DependencyFile.new(name: "../shared.tf", content: "original", directory: directory),
            Dependabot::DependencyFile.new(name: "../deleted.tf", content: "remove me", directory: directory)
          ]
        end
      end
      let(:received_files_by_directory) { {} }

      before do
        received_files = received_files_by_directory
        Dependabot::FileUpdaters.register(
          "terraform",
          Class.new(Dependabot::FileUpdaters::Base) do
            define_method(:updated_dependency_files) do
              directory = dependency_files.first.directory
              received_files[directory] ||= dependency_files.map(&:dup)

              if directory == "/dir1"
                shared_file = dependency_files.find { |file| file.name == "../shared.tf" }.dup
                shared_file.content = "c2hhcmVk"
                shared_file.content_encoding = Dependabot::DependencyFile::ContentEncoding::BASE64
                shared_file.mode = Dependabot::DependencyFile::Mode::EXECUTABLE

                deleted_file = dependency_files.find { |file| file.name == "../deleted.tf" }.dup
                deleted_file.content = nil
                deleted_file.operation = Dependabot::DependencyFile::Operation::DELETE

                created_file = Dependabot::DependencyFile.new(
                  name: "../created.tf",
                  content: nil,
                  directory: directory,
                  type: "symlink",
                  symlink_target: "target.tf",
                  operation: Dependabot::DependencyFile::Operation::CREATE,
                  mode: Dependabot::DependencyFile::Mode::SYMLINK
                )
                [shared_file, deleted_file, created_file]
              else
                created_file = dependency_files.find { |file| file.name == "../created.tf" }.dup
                created_file.operation = Dependabot::DependencyFile::Operation::UPDATE
                [
                  Dependabot::DependencyFile.new(name: "main.tf", content: "# updated", directory: directory),
                  created_file
                ]
              end
            end
            define_method(:check_required_files) { nil }
          end
        )
      end

      it "passes the complete working file set to the next directory" do
        dependency_change = nil
        allow(mock_service).to receive(:create_pull_request) { |change| dependency_change = change }

        create_operation.perform

        second_directory_files = received_files_by_directory.fetch("/dir2")
        expect(second_directory_files.map(&:name)).not_to include("../deleted.tf")

        shared_file = second_directory_files.find { |file| file.name == "../shared.tf" }
        expect(shared_file).to have_attributes(
          content: "c2hhcmVk",
          content_encoding: Dependabot::DependencyFile::ContentEncoding::BASE64,
          mode: Dependabot::DependencyFile::Mode::EXECUTABLE
        )

        created_file = second_directory_files.find { |file| file.name == "../created.tf" }
        expect(created_file).to have_attributes(
          directory: "/dir2",
          operation: Dependabot::DependencyFile::Operation::CREATE,
          type: "symlink",
          symlink_target: "target.tf",
          mode: Dependabot::DependencyFile::Mode::SYMLINK
        )

        changed_files_by_path = dependency_change.updated_dependency_files.to_h { |file| [file.path, file] }
        expect(changed_files_by_path.fetch("/deleted.tf").operation)
          .to eq(Dependabot::DependencyFile::Operation::DELETE)
        expect(changed_files_by_path.fetch("/created.tf").operation)
          .to eq(Dependabot::DependencyFile::Operation::CREATE)
      end
    end

    context "when no directory produces a change" do
      before do
        # Re-register an update checker whose updates are missing a previous version and
        # leave requirements unchanged. compile_all_dependency_changes_for then fails its
        # all_have_previous_version? check and returns nil for every directory, so the
        # multi-directory filter_map collapses to an empty array (the crash condition).
        Dependabot::UpdateCheckers.register(
          "terraform",
          Class.new(Dependabot::UpdateCheckers::Base) do
            define_method(:latest_version) { Gem::Version.new("5.0.0") }
            define_method(:latest_resolvable_version) { Gem::Version.new("5.0.0") }
            define_method(:latest_resolvable_version_with_no_unlock) { Gem::Version.new("5.0.0") }
            define_method(:lowest_security_fix_version) { nil }
            define_method(:lowest_resolvable_security_fix_version) { nil }
            define_method(:updated_requirements) { dependency.requirements }
            define_method(:up_to_date?) { false }
            define_method(:requirements_unlocked_or_can_be?) { true }
            define_method(:can_update?) { |**_kwargs| true }
            define_method(:updated_dependencies) do |**_kwargs|
              [Dependabot::Dependency.new(
                name: dependency.name,
                version: "5.0.0",
                requirements: dependency.requirements,
                previous_version: nil,
                previous_requirements: dependency.requirements,
                package_manager: "terraform",
                directory: dependency.directory
              )]
            end
          end
        )
      end

      it "returns nil so the caller marks the group handled, without opening a PR" do
        expect(mock_service).not_to receive(:create_pull_request)

        result = "unset"
        expect { result = create_operation.perform }.not_to raise_error

        # nil (not an empty DependencyChange) is what GroupUpdateAllVersions keys on to
        # mark the group handled, so assert it directly rather than just "no PR".
        expect(result).to be_nil
      end
    end
  end

  describe "#perform with Maven directories that share a parent POM" do
    subject(:create_operation) do
      described_class.new(
        service: mock_service,
        job: job,
        dependency_snapshot: dependency_snapshot,
        error_handler: mock_error_handler,
        group: dependency_group
      )
    end

    let(:directories) { ["/", "/module-b", "/module-a"] }
    let(:versions) do
      {
        "junit:junit" => "4.13.2",
        "org.springframework:spring-core" => "5.3.39",
        "com.fasterxml.jackson.core:jackson-databind" => "2.9.10.8",
        "org.mybatis:mybatis" => "3.5.19"
      }
    end
    let(:root_pom) { fixture("maven_multi_directory_group/pom.xml") }
    let(:module_a_pom) { fixture("maven_multi_directory_group/module-a/pom.xml") }
    let(:module_b_pom) { fixture("maven_multi_directory_group/module-b/pom.xml") }
    let(:dependency_files) do
      [
        dependency_file("pom.xml", root_pom, "/"),
        dependency_file("module-a/pom.xml", module_a_pom, "/"),
        dependency_file("module-b/pom.xml", module_b_pom, "/"),
        dependency_file("pom.xml", module_b_pom, "/module-b"),
        dependency_file("../pom.xml", root_pom, "/module-b"),
        dependency_file("pom.xml", module_a_pom, "/module-a"),
        dependency_file("../pom.xml", root_pom, "/module-a")
      ]
    end
    let(:job) do
      Dependabot::Job.new_update_job(
        job_id: "1234",
        job_definition: {
          "job" => {
            "package-manager" => "maven",
            "source" => {
              "provider" => "github",
              "repo" => "test/maven-monorepo",
              "directories" => directories,
              "branch" => nil,
              "api-endpoint" => "https://api.github.com/",
              "hostname" => "github.com"
            },
            "dependencies" => versions.keys,
            "existing-pull-requests" => [],
            "existing-group-pull-requests" => [],
            "updating-a-pull-request" => false,
            "lockfile-only" => false,
            "update-subdependencies" => false,
            "ignore-conditions" => [],
            "requirements-update-strategy" => nil,
            "allowed-updates" => [{ "dependency-type" => "all", "update-type" => "all" }],
            "credentials-metadata" => [],
            "security-advisories" => versions.map do |name, _version|
              {
                "dependency-name" => name,
                "affected-versions" => [">= 0"],
                "patched-versions" => [],
                "unaffected-versions" => []
              }
            end,
            "vendor-dependencies" => false,
            "experiments" => {},
            "reject-external-code" => false,
            "commit-message-options" => {},
            "security-updates-only" => true,
            "dependency-groups" => [{
              "name" => "maven",
              "rules" => { "patterns" => versions.keys },
              "applies-to" => "security-updates"
            }]
          }
        }
      )
    end
    let(:dependency_snapshot) do
      Dependabot::DependencySnapshot.create_from_job_definition(
        job: job,
        fetched_files: Dependabot::FetchedFiles.new(
          base_commit_sha: "mock-sha",
          dependency_files: dependency_files
        )
      )
    end
    let(:dependency_group) { dependency_snapshot.groups.find { |group| group.name == "maven" } }
    let(:mock_service) do
      instance_double(
        Dependabot::Service,
        record_ecosystem_meta: nil,
        record_cooldown_meta: nil
      )
    end
    let(:mock_error_handler) do
      instance_double(Dependabot::Updater::ErrorHandler, handle_dependency_error: nil)
    end
    let(:update_checker) do
      available_versions = versions
      Class.new(Dependabot::UpdateCheckers::Base) do
        define_method(:updated_version) { available_versions.fetch(dependency.name) }
        define_method(:latest_version) { Dependabot::Maven::Version.new(updated_version) }
        define_method(:latest_resolvable_version) { latest_version }
        define_method(:latest_resolvable_version_with_no_unlock) { latest_version }
        define_method(:lowest_security_fix_version) { latest_version }
        define_method(:lowest_resolvable_security_fix_version) { latest_version }
        define_method(:updated_requirements) do
          dependency.requirements.map { |requirement| requirement.merge(requirement: updated_version) }
        end
        define_method(:up_to_date?) { false }
        define_method(:requirements_unlocked_or_can_be?) { true }
        define_method(:can_update?) { |**_kwargs| true }
        define_method(:updated_dependencies) do |**_kwargs|
          [Dependabot::Dependency.new(
            name: dependency.name,
            version: updated_version,
            requirements: updated_requirements,
            previous_version: dependency.version,
            previous_requirements: dependency.requirements,
            package_manager: "maven",
            directory: dependency.directory
          )]
        end
      end
    end

    before do
      allow(Dependabot::UpdateCheckers).to receive(:for_package_manager).with("maven").and_return(update_checker)
    end

    it "combines every property update in the shared root POM" do
      dependency_change = nil
      allow(mock_service).to receive(:create_pull_request) { |change| dependency_change = change }

      expect(dependency_group.dependencies.map(&:name).uniq).to match_array(versions.keys)
      create_operation.perform

      dependency_counts = dependency_change.updated_dependencies
                                           .group_by(&:directory)
                                           .transform_values { |dependencies| dependencies.map(&:name).uniq.count }
      expect(dependency_counts).to eq("/" => 4, "/module-b" => 3, "/module-a" => 2)

      root_files = dependency_change.updated_dependency_files.select { |file| file.path == "/pom.xml" }
      expect(root_files.length).to eq(1)
      expect(root_files.first.content).to include(
        "<junit.version>4.13.2</junit.version>",
        "<spring.version>5.3.39</spring.version>",
        "<fasterxml-jackson.version>2.9.10.8</fasterxml-jackson.version>",
        "<mybatis.version>3.5.19</mybatis.version>"
      )
    end

    def dependency_file(name, content, directory)
      Dependabot::DependencyFile.new(name: name, content: content, directory: directory)
    end
  end
end
