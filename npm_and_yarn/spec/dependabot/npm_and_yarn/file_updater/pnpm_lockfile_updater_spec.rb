# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/npm_and_yarn/file_updater/pnpm_lockfile_updater"

RSpec.describe Dependabot::NpmAndYarn::FileUpdater::PnpmLockfileUpdater do
  subject(:updated_pnpm_lock_content) { updater.updated_pnpm_lock_content(pnpm_lock) }

  let(:updater) do
    described_class.new(
      dependency_files: files,
      dependencies: dependencies,
      credentials: credentials,
      repo_contents_path: repo_contents_path
    )
  end
  let(:dependencies) { [dependency] }

  let(:credentials) do
    [Dependabot::Credential.new({
      "type" => "git_source",
      "host" => "github.com"
    })]
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

  let(:files) { project_dependency_files(project_name) }

  let(:pnpm_lock) do
    files.find { |f| f.name == "pnpm-lock.yaml" }
  end

  let(:tmp_path) { Dependabot::Utils::BUMP_TMP_DIR_PATH }

  let(:repo_contents_path) { build_tmp_repo(project_name, path: "projects") }

  before { FileUtils.mkdir_p(tmp_path) }

  describe "errors" do
    context "with a dependency version that can't be found" do
      let(:project_name) { "pnpm/yanked_version" }

      it "raises a helpful error" do
        expect { updated_pnpm_lock_content }
          .to raise_error(Dependabot::DependencyFileNotResolvable)
      end
    end

    context "with an invalid requirement in the package.json" do
      let(:project_name) { "pnpm/invalid_requirement" }

      it "raises a helpful error" do
        expect { updated_pnpm_lock_content }
          .to raise_error(Dependabot::DependencyFileNotResolvable)
      end
    end

    context "when there is a lockfile with tarball urls we don't have access to" do
      let(:project_name) { "pnpm/private_tarball_urls" }

      it "raises a helpful error" do
        expect { updated_pnpm_lock_content }
          .to raise_error(Dependabot::PrivateSourceAuthenticationFailure)
      end
    end

    context "with a dependency that can't be found" do
      let(:project_name) { "pnpm/nonexistent_dependency_yanked_version" }

      it "raises a helpful error" do
        expect { updated_pnpm_lock_content }
          .to raise_error(Dependabot::PrivateSourceAuthenticationFailure)
      end
    end

    context "with a locked dependency that can't be found" do
      let(:dependency_name) { "@googleapis/youtube" }
      let(:version) { "13.0.0" }
      let(:previous_version) { "10.1.0" }
      let(:requirements) do
        [{
          file: "package.json",
          requirement: "^13.0.0",
          groups: ["dependencies"],
          source: nil
        }]
      end
      let(:previous_requirements) do
        [{
          file: "package.json",
          requirement: "^10.1.0",
          groups: ["dependencies"],
          source: nil
        }]
      end

      let(:project_name) { "pnpm/nonexistent_locked_dependency" }

      it "raises a helpful error" do
        expect { updated_pnpm_lock_content }
          .to raise_error(Dependabot::PrivateSourceAuthenticationFailure)
      end
    end

    context "with a private git dep we don't have access to" do
      let(:dependency_name) { "cross-fetch" }
      let(:version) { "4.0.0" }
      let(:previous_version) { "3.1.5" }
      let(:requirements) do
        [{
          file: "package.json",
          requirement: "^4.0.0",
          groups: ["dependencies"],
          source: nil
        }]
      end
      let(:previous_requirements) do
        [{
          file: "package.json",
          requirement: "^3.1.5",
          groups: ["dependencies"],
          source: nil
        }]
      end

      let(:project_name) { "pnpm/github_dependency_private" }

      it "raises a helpful error" do
        expect { updated_pnpm_lock_content }
          .to raise_error(Dependabot::GitDependenciesNotReachable) do |error|
          expect(error.dependency_urls)
            .to eq(
              [
                "https://github.com/Zelcord/electron-context-menu"
              ]
            )
        end
      end
    end

    context "with a private git dep we don't have access to in PNPM v8" do
      let(:dependency_name) { "cross-fetch" }
      let(:version) { "4.0.0" }
      let(:previous_version) { "3.1.5" }
      let(:requirements) do
        [{
          file: "package.json",
          requirement: "^4.0.0",
          groups: ["dependencies"],
          source: nil
        }]
      end
      let(:previous_requirements) do
        [{
          file: "package.json",
          requirement: "^3.1.5",
          groups: ["dependencies"],
          source: nil
        }]
      end

      let(:project_name) { "pnpm/github_dependency_private_v8" }

      it "raises a helpful error" do
        expect { updated_pnpm_lock_content }
          .to raise_error(Dependabot::GitDependenciesNotReachable) do |error|
          expect(error.dependency_urls)
            .to eq(
              [
                "https://github.com/Zelcord/electron-context-menu"
              ]
            )
        end
      end
    end

    context "with a GHPR registry incorrectly configured including the scope" do
      let(:dependency_name) { "@dsp-testing/inner-source-top-secret-npm-2" }
      let(:version) { "1.0.9" }
      let(:previous_version) { "1.0.8" }
      let(:requirements) do
        [{
          file: "package.json",
          requirement: "1.0.9",
          groups: ["dependencies"],
          source: nil
        }]
      end
      let(:previous_requirements) do
        [{
          file: "package.json",
          requirement: "1.0.8",
          groups: ["dependencies"],
          source: nil
        }]
      end

      let(:project_name) { "pnpm/private_registry_ghpr" }

      it "raises a helpful error" do
        expect { updated_pnpm_lock_content }
          .to raise_error(Dependabot::PrivateSourceAuthenticationFailure)
      end
    end

    context "with a private registry with no configuration" do
      let(:dependency_name) { "next" }
      let(:version) { "14.2.4" }
      let(:previous_version) { "13.2.4" }
      let(:requirements) do
        [{
          file: "package.json",
          requirement: "^14.2.4",
          groups: ["dependencies"],
          source: nil
        }]
      end
      let(:previous_requirements) do
        [{
          file: "package.json",
          requirement: "^13.2.4",
          groups: ["dependencies"],
          source: nil
        }]
      end

      let(:project_name) { "pnpm/private_registry_no_config" }

      it "raises a helpful error" do
        expect { updated_pnpm_lock_content }
          .to raise_error(Dependabot::DependencyNotFound)
      end
    end
  end
end
