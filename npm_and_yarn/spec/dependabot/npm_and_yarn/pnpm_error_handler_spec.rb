# typed: false
# frozen_string_literal: true

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
  end
end
