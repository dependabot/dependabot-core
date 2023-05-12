# frozen_string_literal: true

require "spec_helper"
require "dependabot/npm_and_yarn/file_updater/pnpm_lockfile_updater"

RSpec.describe Dependabot::NpmAndYarn::FileUpdater::PnpmLockfileUpdater do
  let(:updater) do
    described_class.new(
      dependency_files: files,
      dependencies: dependencies,
      credentials: credentials,
      repo_contents_path: nil
    )
  end
  let(:dependencies) { [dependency] }

  let(:credentials) do
    [{
      "type" => "git_source",
      "host" => "github.com"
    }]
  end
  let(:dependency) do
    Dependabot::Dependency.new(
      name: dependency_name,
      version: version,
      previous_version: previous_version,
      requirements: requirements,
      previous_requirements: previous_requirements,
      package_manager: "npm_and_yarn"
    )
  end
  let(:dependency_name) { "fetch-factory" }
  let(:version) { "0.0.2" }
  let(:previous_version) { "0.0.1" }
  let(:requirements) do
    [{
      file: "package.json",
      requirement: "^0.0.2",
      groups: ["dependencies"],
      source: nil
    }]
  end
  let(:previous_requirements) do
    [{
      file: "package.json",
      requirement: "^0.0.1",
      groups: ["dependencies"],
      source: nil
    }]
  end
  let(:pnpm_lock) do
    files.find { |f| f.name == "pnpm-lock.yaml" }
  end

  let(:tmp_path) { Dependabot::Utils::BUMP_TMP_DIR_PATH }

  before { FileUtils.mkdir_p(tmp_path)  }

  subject(:updated_pnpm_lock_content) { updater.updated_pnpm_lock_content(pnpm_lock) }

  describe "errors" do
    context "with a dependency version that can't be found" do
      let(:files) { project_dependency_files("pnpm/yanked_version") }

      it "raises a helpful error" do
        expect { updated_pnpm_lock_content }.
          to raise_error(Dependabot::DependencyFileNotResolvable)
      end
    end

    context "with an invalid requirement in the package.json" do
      let(:files) { project_dependency_files("pnpm/invalid_requirement") }

      it "raises a helpful error" do
        expect { updated_pnpm_lock_content }.
          to raise_error(Dependabot::DependencyFileNotResolvable)
      end
    end

    context "with a dependency that can't be found" do
      let(:files) { project_dependency_files("pnpm/nonexistent_dependency_yanked_version") }

      it "raises a helpful error" do
        expect { updated_pnpm_lock_content }.
          to raise_error(Dependabot::PrivateSourceAuthenticationFailure)
      end
    end
  end
end
