# typed: false
# frozen_string_literal: true

# Sorbet cannot resolve the child-context-only error_message fixture used by the parent hook.

require "spec_helper"
require "dependabot/npm_and_yarn/file_updater/pnpm_lockfile_updater"
require "dependabot/npm_and_yarn/dependency_files_filterer"
require "dependabot/dependency"
require "dependabot/dependency_file"
require "dependabot/shared_helpers"
require "dependabot/errors"

RSpec.describe Dependabot::NpmAndYarn::PnpmErrorHandler do
  subject(:error_handler) { described_class.new(dependencies: dependencies, dependency_files: dependency_files) }

  let(:dependencies) { [dependency] }
  let(:error) { instance_double(Dependabot::SharedHelpers::HelperSubprocessFailed, message: error_message) }

  let(:dependency) do
    Dependabot::Dependency.new(
      name: dependency_name,
      version: version,
      requirements: [],
      previous_requirements: [],
      package_manager: "npm_and_yarn"
    )
  end
  let(:dependency_files) { project_dependency_files("pnpm/git_dependency_local_file") }

  let(:credentials) do
    [Dependabot::Credential.new(
      {
        "type" => "git_source",
        "host" => "github.com"
      }
    )]
  end

  let(:dependency_name) { "@segment/analytics.js-integration-facebook-pixel" }
  let(:version) { "github:segmentio/analytics.js-integrations#2.4.1" }
  let(:yarn_lock) do
    dependency_files.find { |f| f.name == "pnpm.lock" }
  end

  describe "#initialize" do
    it "initializes with dependencies and dependency files" do
      expect(error_handler.send(:dependencies)).to eq(dependencies)
      expect(error_handler.send(:dependency_files)).to eq(dependency_files)
    end
  end

  describe "#handle_error" do
    context "when the error message contains Inconsistent Registry Response" do
      let(:error_message) do
        "ECONNRESET  request to https://artifactory.schaeffler.com/as.zip failed, reason: socket hang up"
      end

      it "raises a InconsistentRegistryResponse error with the correct message" do
        expect do
          error_handler.handle_pnpm_error(error)
        end.to raise_error(Dependabot::InconsistentRegistryResponse)
      end
    end

    context "when the error message contains package error" do
      let(:error_message) do
        "ERR_PNPM_NO_VERSIONS  No versions available for prosemirror-gapcursor. The package may be unpublished."
      end

      it "raises a DependencyFileNotResolvable error with the correct message" do
        expect do
          error_handler.handle_pnpm_error(error)
        end.to raise_error(Dependabot::DependencyFileNotResolvable)
      end
    end

    {
      %w(pnpm10 missing_tarball_integrity) => %w(
        xlsx https://cdn.sheetjs.com/xlsx-0.20.3/xlsx-0.20.3.tgz
      ),
      %w(pnpm11 missing_tarball_integrity) => %w(
        @example/widget https://github.com/example/widget/releases/download/v1.0.0/build.tgz
      )
    }.each do |(version_dir, scenario), (package, source)|
      context "when a tarball dependency has no integrity (#{version_dir} output)" do
        let(:dependency_files) { project_dependency_files("pnpm/simple") }
        let(:error_message) { fixture("pnpm_errors", version_dir, "#{scenario}.txt") }

        it "raises DependencyFileNotResolvable naming the package, its source and the lockfile" do
          expect { error_handler.handle_pnpm_error(error) }
            .to raise_error(Dependabot::DependencyFileNotResolvable) do |raised|
              expect(raised.message).to include(package, source, "pnpm-lock.yaml")
            end
        end

        it "does not advise regenerating the lockfile without verification" do
          expect { error_handler.handle_pnpm_error(error) }
            .to raise_error(Dependabot::DependencyFileNotResolvable) do |raised|
              expect(raised.message).not_to include("delete")
            end
        end
      end
    end

    {
      "bad_runtime_version" => %w(26 v24.21.0),
      "bad_runtime_version_exact" => %w(24.21.0 v24.22.0)
    }.each do |scenario, (required, current)|
      context "when the repository requires a Node.js version Dependabot does not run (#{scenario})" do
        let(:error_message) { fixture("pnpm_errors", "pnpm12", "#{scenario}.txt") }

        it "raises ToolVersionNotSupported with the required and current versions" do
          expect { error_handler.handle_pnpm_error(error) }
            .to raise_error(Dependabot::ToolVersionNotSupported) do |raised|
              expect(raised.tool_name).to eq("Node")
              expect(raised.detected_version).to eq(required)
              expect(raised.supported_versions).to eq(current)
            end
        end
      end
    end

    context "when the runtime error does not state the versions" do
      let(:error_message) { "Error: ERR_PNPM_BAD_RUNTIME_VERSION\n\n  × Something unexpected happened" }

      it "leaves the error for the caller to re-raise" do
        expect { error_handler.handle_pnpm_error(error) }.not_to raise_error
      end
    end

    context "when the workspace configuration is invalid" do
      let(:dependency_files) { project_dependency_files("pnpm/workspaces") }
      let(:error_message) { fixture("pnpm_errors", "pnpm10", "invalid_workspace_configuration.txt") }

      it "raises DependencyFileNotResolvable naming pnpm-workspace.yaml and pnpm's reason" do
        expect { error_handler.handle_pnpm_error(error) }
          .to raise_error(Dependabot::DependencyFileNotResolvable) do |raised|
            expect(raised.message).to include("pnpm-workspace.yaml", "packages field missing or empty")
          end
      end
    end

    context "when pnpm only warns about an unsupported engine before an unrelated error" do
      let(:error_message) do
        "[WARN] Unsupported engine: wanted: {\"node\":\"22\"} (current: {\"node\":\"v24.22.0\"})\n" \
          "[ERR_PNPM_SOMETHING_ELSE] Something else failed"
      end

      it "does not classify the warning" do
        expect { error_handler.handle_pnpm_error(error) }.not_to raise_error
      end
    end
  end
end
