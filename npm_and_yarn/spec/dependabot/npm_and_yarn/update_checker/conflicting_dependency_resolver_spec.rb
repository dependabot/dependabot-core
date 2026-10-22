# typed: strict
# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency"
require "dependabot/dependency_file"
require "dependabot/npm_and_yarn/update_checker/conflicting_dependency_resolver"

# Sorbet fixture signatures must stay beside their lets and use concrete types.
# rubocop:disable-next RSpec/ScatteredLet, RSpec/DescribedClass
RSpec.describe(Dependabot::NpmAndYarn::UpdateChecker::ConflictingDependencyResolver) do
  extend T::Sig

  sig { returns(T::Array[Dependabot::DependencyFile]) }
  let(:dependency_files) { raise "Specify dependency files in the example context" }

  sig { returns(Dependabot::NpmAndYarn::UpdateChecker::ConflictingDependencyResolver) }
  let(:resolver) do
    described_class.new(
      dependency_files: dependency_files,
      credentials: [Dependabot::Credential.new(
        {
          "type" => "git_source",
          "host" => "github.com",
          "username" => "x-access-token",
          "password" => "token"
        }
      )]
    )
  end
  sig { returns(Dependabot::Dependency) }
  let(:dependency) do
    Dependabot::Dependency.new(
      name: dependency_name,
      version: current_version,
      requirements: [],
      package_manager: "npm_and_yarn"
    )
  end
  sig { returns(String) }
  let(:dependency_name) { "abind" }
  sig { returns(String) }
  let(:current_version) { "1.0.5" }
  sig { returns(String) }
  let(:target_version) { "2.0.0" }
  sig { returns(T::Boolean) }
  let(:enable_yarn_berry_conflicting_dependencies) { true }

  before do
    allow(Dependabot::Experiments).to receive(:enabled?)
      .with(:enable_yarn_berry_conflicting_dependencies)
      .and_return(enable_yarn_berry_conflicting_dependencies)
  end

  describe "#conflicting_dependencies" do
    sig { returns(T::Array[Dependabot::UpdateCheckers::Conflict]) }
    subject(:conflicting_dependencies) do
      resolver.conflicting_dependencies(
        dependency: dependency,
        target_version: target_version
      )
    end

    context "with npm lockfiles" do
      sig { returns(T::Array[Dependabot::DependencyFile]) }
      let(:dependency_files) { project_dependency_files("npm6/subdependency_out_of_range_gt") }

      it "passes the installed version to the npm helper when enabled" do
        allow(Dependabot::SharedHelpers).to receive(:run_helper_subprocess).and_return([])

        expect(conflicting_dependencies).to be_empty
        expect(Dependabot::SharedHelpers).to have_received(:run_helper_subprocess).with(
          command: Dependabot::NpmAndYarn::NativeHelpers.helper_path,
          function: "npm:findConflictingDependencies",
          args: [a_kind_of(String), dependency_name, target_version, current_version]
        )
      end

      context "when the experiment is disabled" do
        sig { returns(T::Boolean) }
        let(:enable_yarn_berry_conflicting_dependencies) { false }

        it "passes the original unscoped npm helper arguments" do
          allow(Dependabot::SharedHelpers).to receive(:run_helper_subprocess).and_return([])

          expect(conflicting_dependencies).to be_empty
          expect(Dependabot::SharedHelpers).to have_received(:run_helper_subprocess).with(
            command: Dependabot::NpmAndYarn::NativeHelpers.helper_path,
            function: "npm:findConflictingDependencies",
            args: [a_kind_of(String), dependency_name, target_version]
          )
        end
      end

      it "returns the right array of blocking dependencies" do
        expect(conflicting_dependencies).to contain_exactly(
          {
            "explanation" => "objnest@4.1.2 requires abind@^1.0.0",
            "name" => "objnest",
            "version" => "4.1.2",
            "requirement" => "^1.0.0"
          }
        )
      end

      context "with no blocking dependencies" do
        sig { returns(String) }
        let(:target_version) { "1.0.0" }

        it "returns an empty array" do
          expect(conflicting_dependencies).to be_empty
        end
      end

      context "when the conflicting dependency helper fails" do
        sig { returns(Dependabot::SharedHelpers::HelperSubprocessFailed) }
        let(:helper_error) do
          Dependabot::SharedHelpers::HelperSubprocessFailed.new(
            message: "unexpected helper failure",
            error_context: {}
          )
        end

        before do
          allow(Dependabot::SharedHelpers).to receive(:run_helper_subprocess).and_raise(helper_error)
        end

        it "uses the legacy error fallback" do
          expect(conflicting_dependencies).to be_empty
        end
      end
    end

    context "with yarn lockfiles" do
      sig { returns(T::Array[Dependabot::DependencyFile]) }
      let(:dependency_files) { project_dependency_files("yarn/subdependency_out_of_range_gt") }

      it "returns the right array of blocking dependencies" do
        expect(conflicting_dependencies).to contain_exactly(
          {
            "explanation" => "objnest@4.1.4 requires abind@^1.0.0",
            "name" => "objnest",
            "requirement" => "^1.0.0",
            "version" => "4.1.4"
          }
        )
      end

      context "when the yarn berry conflicting dependencies experiment is disabled" do
        sig { returns(T::Boolean) }
        let(:enable_yarn_berry_conflicting_dependencies) { false }

        it "still returns yarn v1 blocking dependencies" do
          expect(Dependabot::SharedHelpers).to receive(:run_helper_subprocess)
            .with(
              hash_including(
                function: "yarn:findConflictingDependencies",
                args: [a_kind_of(String), dependency_name, target_version, false]
              )
            )
            .and_call_original

          expect(conflicting_dependencies).not_to be_empty
        end
      end
    end

    context "with unquoted Yarn v1 descriptors for multiple installed versions" do
      sig { returns(T::Array[Dependabot::DependencyFile]) }
      let(:dependency_files) { project_dependency_files("yarn/multiple_brace_expansion_versions") }
      sig { returns(String) }
      let(:dependency_name) { "brace-expansion" }
      sig { returns(String) }
      let(:current_version) { "2.1.2" }
      sig { returns(String) }
      let(:target_version) { "2.1.4" }

      it "does not report unrelated installed versions as conflicts" do
        expect(conflicting_dependencies).to be_empty
      end

      context "when the targeted version is pinned" do
        sig { returns(T::Array[Dependabot::DependencyFile]) }
        let(:dependency_files) do
          files = T.let(super(), T::Array[Dependabot::DependencyFile])
          files.map do |file|
            file.dup.tap { |copy| copy.content = T.must(file.content).gsub("^2.0.2", "2.1.2") }
          end
        end

        it "retains the incompatible requirement on the targeted version" do
          expect(conflicting_dependencies).to contain_exactly(
            {
              "explanation" => "current-parent@1.0.0 requires brace-expansion@2.1.2",
              "name" => "current-parent",
              "version" => "1.0.0",
              "requirement" => "2.1.2"
            }
          )
        end
      end

      context "when the experiment is disabled" do
        sig { returns(T::Boolean) }
        let(:enable_yarn_berry_conflicting_dependencies) { false }

        it "retains the legacy unscoped conflict checks" do
          expect(conflicting_dependencies.map { |conflict| conflict.fetch("name") })
            .to contain_exactly("legacy-parent", "modern-parent")
        end
      end
    end

    context "with yarn berry lockfiles" do
      sig { returns(T::Array[Dependabot::DependencyFile]) }
      let(:dependency_files) { project_dependency_files("yarn_berry/subdependency_out_of_range_gt") }

      it "returns the right array of blocking dependencies" do
        expect(conflicting_dependencies).to contain_exactly(
          {
            "explanation" => "objnest@4.1.4 requires abind@^1.0.0",
            "name" => "objnest",
            "requirement" => "^1.0.0",
            "version" => "4.1.4"
          }
        )
      end

      context "with no blocking dependencies" do
        sig { returns(String) }
        let(:target_version) { "1.0.0" }

        it "returns an empty array" do
          expect(conflicting_dependencies).to be_empty
        end
      end

      context "when the yarn berry conflicting dependencies experiment is disabled" do
        sig { returns(T::Boolean) }
        let(:enable_yarn_berry_conflicting_dependencies) { false }

        it "uses the legacy Yarn helper" do
          expect(Dependabot::SharedHelpers).to receive(:run_helper_subprocess)
            .with(
              hash_including(
                function: "yarn:findConflictingDependencies",
                args: [a_kind_of(String), dependency_name, target_version, false]
              )
            )
            .and_call_original

          expect(conflicting_dependencies).to be_empty
        end
      end
    end

    context "with no lockfile" do
      sig { returns(T::Array[Dependabot::DependencyFile]) }
      let(:dependency_files) do
        project_dependency_files("yarn/subdependency_out_of_range_gt")
          .select { |file| file.name == "package.json" }
      end

      it "uses the legacy Yarn traversal" do
        expect(Dependabot::SharedHelpers).to receive(:run_helper_subprocess)
          .with(
            hash_including(
              function: "yarn:findConflictingDependencies",
              args: [a_kind_of(String), dependency_name, target_version, false, current_version]
            )
          )
          .and_call_original

        expect(conflicting_dependencies).to be_empty
      end
    end

    context "with pnpm lockfiles" do
      sig { returns(T::Array[Dependabot::DependencyFile]) }
      let(:dependency_files) { project_dependency_files("pnpm/multiple_sub_dependencies") }

      it "uses the legacy Yarn traversal" do
        expect(Dependabot::SharedHelpers).to receive(:run_helper_subprocess)
          .with(
            hash_including(
              function: "yarn:findConflictingDependencies",
              args: [a_kind_of(String), dependency_name, target_version, false, current_version]
            )
          )
          .and_call_original

        expect(conflicting_dependencies).to be_empty
      end
    end

    context "when preparing dependency files fails" do
      sig { returns(T::Array[Dependabot::DependencyFile]) }
      let(:dependency_files) { project_dependency_files("yarn/subdependency_out_of_range_gt") }
      sig { returns(RSpec::Mocks::InstanceVerifyingDouble) }
      let(:dependency_files_builder) do
        instance_double(Dependabot::NpmAndYarn::UpdateChecker::DependencyFilesBuilder)
      end
      sig { returns(Dependabot::SharedHelpers::HelperSubprocessFailed) }
      let(:helper_error) do
        Dependabot::SharedHelpers::HelperSubprocessFailed.new(
          message: "failed to prepare dependency files",
          error_context: {}
        )
      end

      before do
        allow(Dependabot::NpmAndYarn::UpdateChecker::DependencyFilesBuilder)
          .to receive(:new).and_return(dependency_files_builder)
        allow(dependency_files_builder).to receive(:write_temporary_dependency_files).and_raise(helper_error)
      end

      it "uses the legacy preparation fallback even when the experiment is enabled" do
        expect(conflicting_dependencies).to be_empty
      end
    end

    context "when the conflicting dependency helper fails" do
      sig { returns(T::Array[Dependabot::DependencyFile]) }
      let(:dependency_files) { project_dependency_files("yarn/subdependency_out_of_range_gt") }
      sig { returns(Dependabot::SharedHelpers::HelperSubprocessFailed) }
      let(:helper_error) do
        Dependabot::SharedHelpers::HelperSubprocessFailed.new(
          message: "unexpected helper failure",
          error_context: {}
        )
      end

      before do
        allow(Dependabot::SharedHelpers).to receive(:run_helper_subprocess).and_raise(helper_error)
      end

      it "raises the helper error" do
        expect { conflicting_dependencies }.to raise_error(helper_error)
      end
    end
  end
end
