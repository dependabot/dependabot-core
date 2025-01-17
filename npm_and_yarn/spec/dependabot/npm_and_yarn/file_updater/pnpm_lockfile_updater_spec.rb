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

  # Variable to control the enabling feature flag for the corepack fix
  let(:enable_corepack_for_npm_and_yarn) { true }

  before do
    FileUtils.mkdir_p(tmp_path)
    allow(Dependabot::Experiments).to receive(:enabled?)
      .with(:enable_corepack_for_npm_and_yarn).and_return(enable_corepack_for_npm_and_yarn)
    allow(Dependabot::Experiments).to receive(:enabled?)
      .with(:enable_shared_helpers_command_timeout).and_return(true)
  end

  after do
    Dependabot::Experiments.reset!
  end

  describe "errors" do
    before do
      allow(Dependabot::Experiments).to receive(:enabled?)
        .with(:enable_fix_for_pnpm_no_change_error).and_return(true)
    end

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

    context "when there is a lockfile with tarball urls we don't have access to" do
      let(:project_name) { "pnpm/private_package_access" }

      it "raises a helpful error" do
        expect { updated_pnpm_lock_content }
          .to raise_error(Dependabot::PrivateSourceAuthenticationFailure)
      end
    end

    context "when there is a unsupported engine response from registry" do
      let(:dependency_name) { "@blocknote/core" }
      let(:version) { "0.15.4" }
      let(:previous_version) { "0.15.3 " }
      let(:requirements) do
        [{
          file: "package.json",
          requirement: "0.15.4",
          groups: ["dependencies"],
          source: nil
        }]
      end

      let(:project_name) { "pnpm/unsupported_engine" }

      it "raises a helpful error" do
        expect { updated_pnpm_lock_content }
          .to raise_error(Dependabot::ToolVersionNotSupported)
      end
    end

    context "when there is a unsupported engine (npm) response from registry" do
      let(:dependency_name) { "@npmcli/fs" }
      let(:version) { "3.1.1" }
      let(:previous_version) { "3.1.0 " }
      let(:requirements) do
        [{
          file: "package.json",
          requirement: "3.1.1",
          groups: ["devDependencies"],
          source: nil
        }]
      end

      let(:project_name) { "pnpm/unsupported_engine_npm" }

      it "raises a helpful error" do
        expect { updated_pnpm_lock_content }
          .to raise_error(Dependabot::ToolVersionNotSupported)
      end
    end

    context "when there is a private registry we don't have access to" do
      let(:project_name) { "pnpm/private_package_access_with_package_name" }

      it "raises a helpful error" do
        expect { updated_pnpm_lock_content }
          .to raise_error(Dependabot::PrivateSourceAuthenticationFailure)
      end
    end

    context "when there is a private registry we don't have access to and no package name is mentioned" do
      let(:dependency_name) { "rollup" }
      let(:version) { "3.29.5" }
      let(:previous_version) { "^2.79.1" }
      let(:requirements) do
        [{
          file: "package.json",
          requirement: "3.29.5",
          groups: ["devDependencies"],
          source: nil
        }]
      end
      let(:previous_requirements) do
        [{
          file: "package.json",
          requirement: "^2.79.1",
          groups: ["devDependencies"],
          source: nil
        }]
      end
      let(:project_name) { "pnpm/private_dep_access_with_no_package_name" }

      it "raises a helpful error" do
        expect { updated_pnpm_lock_content }
          .to raise_error(Dependabot::DependencyNotFound)
      end
    end

    context "when there is a unsupported engine response (pnpm) from registry" do
      let(:dependency_name) { "eslint" }
      let(:version) { "9.9.0" }
      let(:previous_version) { "8.32.0" }
      let(:requirements) do
        [{
          file: "package.json",
          requirement: "9.9.0",
          groups: ["devDependencies"],
          source: nil
        }]
      end

      let(:project_name) { "pnpm/unsupported_engine_pnpm" }

      it "raises a helpful error" do
        expect { updated_pnpm_lock_content }
          .to raise_error(Dependabot::ToolVersionNotSupported)
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

    context "with an invalid package manager requirement in the package.json" do
      let(:project_name) { "pnpm/invalid_package_manager" }

      it "raises a helpful error" do
        expect { updated_pnpm_lock_content }
          .to raise_error(Dependabot::DependencyFileNotResolvable)
      end
    end

    context "with a registry resolution that returns err_pnpm_tarball_integrity response" do
      let(:dependency_name) { "lodash" }
      let(:version) { "22.2.0" }
      let(:previous_version) { "^20.10.5" }
      let(:requirements) do
        [{
          file: "package.json",
          requirement: "22.2.0",
          groups: ["devDependencies"],
          source: nil
        }]
      end
      let(:previous_requirements) do
        [{
          file: "package.json",
          requirement: "^20.10.5",
          groups: ["devDependencies"],
          source: nil
        }]
      end

      let(:project_name) { "pnpm/tarball_integrity" }

      it "raises a helpful error" do
        expect { updated_pnpm_lock_content }
          .to raise_error(Dependabot::DependencyFileNotResolvable)
      end
    end

    context "with a registry resolution that returns err_pnpm_patch_not_applied response" do
      let(:dependency_name) { "@nx/js" }
      let(:version) { "19.5.7" }
      let(:previous_version) { "18.0.2" }
      let(:requirements) do
        [{
          file: "package.json",
          requirement: "19.5.7",
          groups: ["patchedDependencies"],
          source: nil
        }]
      end
      let(:previous_requirements) do
        [{
          file: "package.json",
          requirement: "18.0.2",
          groups: ["patchedDependencies"],
          source: nil
        }]
      end

      let(:project_name) { "pnpm/patch_not_applied" }

      it "raises a helpful error" do
        expect { updated_pnpm_lock_content }
          .to raise_error(Dependabot::DependencyFileNotResolvable)
      end
    end

    context "with a registry resolution that returns err_pnpm_unsupported_platform response" do
      let(:dependency_name) { "@swc/core-linux-arm-gnueabihf" }
      let(:version) { "1.7.11" }
      let(:previous_version) { "1.3.56" }
      let(:requirements) do
        [{
          file: "package.json",
          requirement: "1.7.11",
          groups: ["optionalDependencies"],
          source: nil
        }]
      end
      let(:previous_requirements) do
        [{
          file: "package.json",
          requirement: "1.3.56",
          groups: ["optionalDependencies"],
          source: nil
        }]
      end

      let(:project_name) { "pnpm/unsupported_platform" }

      it "raises a helpful error" do
        expect { updated_pnpm_lock_content }
          .to raise_error(Dependabot::ToolVersionNotSupported)
      end
    end

    context "when there is a private repo we don't have access to and returns a 4xx error" do
      let(:project_name) { "pnpm/private_repo_no_access" }

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
                "https://github.com/dependabot-fixtures/pnpm_github_dependency_private"
              ]
            )
        end
      end
    end

    context "when there is a private repo returns a 5xx error" do
      let(:project_name) { "pnpm/private_repo_with_server_error" }

      it "raises a helpful error" do
        expect { updated_pnpm_lock_content }
          .to raise_error(Dependabot::PrivateSourceAuthenticationFailure)
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
                "https://github.com/dependabot-fixtures/pnpm_github_dependency_private"
              ]
            )
        end
      end
    end

    context "with an err_pnpm_meta_fetch_fail response" do
      let(:project_name) { "pnpm/meta_fetch_fail" }

      it "raises a helpful error" do
        expect { updated_pnpm_lock_content }
          .to raise_error(Dependabot::DependencyFileNotResolvable)
      end
    end

    context "with a registry resolution that returns missing_workspace_package response" do
      let(:dependency_name) { "@storybook/react-vite" }
      let(:version) { "8.2.9" }
      let(:previous_version) { "8.1.1" }
      let(:requirements) do
        [{
          file: "package.json",
          requirement: "8.2.9",
          groups: ["optionalDependencies"],
          source: nil
        }]
      end
      let(:previous_requirements) do
        [{
          file: "package.json",
          requirement: "8.1.1",
          groups: ["optionalDependencies"],
          source: nil
        }]
      end

      let(:project_name) { "pnpm/missing_workspace_package" }

      it "raises a helpful error" do
        expect { updated_pnpm_lock_content }
          .to raise_error(Dependabot::DependencyFileNotResolvable)
      end
    end

    context "with a registry resolution that returns err_pnpm_broken_metadata_json response" do
      let(:dependency_name) { "nodemon" }
      let(:version) { "3.3.3" }
      let(:previous_version) { "^3.1.3" }
      let(:requirements) do
        [{
          file: "package.json",
          requirement: "3.3.3",
          groups: ["devDependencies"],
          source: nil
        }]
      end
      let(:previous_requirements) do
        [{
          file: "package.json",
          requirement: "^3.1.3",
          groups: ["devDependencies"],
          source: nil
        }]
      end

      let(:project_name) { "pnpm/broken_metadata" }

      it "raises a helpful error" do
        expect { updated_pnpm_lock_content }
          .to raise_error(Dependabot::DependencyFileNotResolvable)
      end
    end

    context "with a registry resolution that returns missing_workspace_dir_package response" do
      let(:dependency_name) { "webpack" }
      let(:version) { "5.94.0" }
      let(:previous_version) { "5.93.0" }
      let(:requirements) do
        [{
          file: "package.json",
          requirement: "5.94.0",
          groups: ["dependencies"],
          source: nil
        }]
      end
      let(:previous_requirements) do
        [{
          file: "package.json",
          requirement: "5.93.0",
          groups: ["dependencies"],
          source: nil
        }]
      end

      let(:project_name) { "pnpm/missing_workspace_dir_package" }

      it "raises a helpful error" do
        expect { updated_pnpm_lock_content }
          .to raise_error(Dependabot::DependencyFileNotResolvable)
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

    context "with a dependency resolution that returns Invalid package.json response" do
      let(:dependency_name) { "@radix-ui/react-context-menu" }
      let(:version) { "2.2.3-rc.12" }
      let(:previous_version) { "^2.2.3" }
      let(:requirements) do
        [{
          file: "package.json",
          requirement: "2.2.3-rc.12",
          groups: ["Dependencies"],
          source: nil
        }]
      end
      let(:previous_requirements) do
        [{
          file: "package.json",
          requirement: "^2.2.3",
          groups: ["Dependencies"],
          source: nil
        }]
      end

      let(:project_name) { "pnpm/invalid_json" }

      it "raises a helpful error" do
        expect { updated_pnpm_lock_content }
          .to raise_error(Dependabot::DependencyFileNotResolvable)
      end
    end

    context "with a dependency resolution that returns invalid YAML response" do
      let(:dependency_name) { "@mdx-js/react" }
      let(:version) { "3.0.2" }
      let(:previous_version) { "^3.0.1" }
      let(:requirements) do
        [{
          file: "package.json",
          requirement: "3.0.2",
          groups: ["Dependencies"],
          source: nil
        }]
      end
      let(:previous_requirements) do
        [{
          file: "package.json",
          requirement: "^3.0.1",
          groups: ["Dependencies"],
          source: nil
        }]
      end

      let(:project_name) { "pnpm/invalid_yaml" }

      it "raises a helpful error" do
        expect { updated_pnpm_lock_content }
          .to raise_error(Dependabot::DependencyFileNotResolvable)
      end
    end

    context "with a dependency resolution that returns unexpected store response" do
      let(:dependency_name) { "hexo" }
      let(:version) { "7.3.1" }
      let(:previous_version) { "^7.3.0" }
      let(:requirements) do
        [{
          file: "package.json",
          requirement: "7.3.1",
          groups: ["Dependencies"],
          source: nil
        }]
      end
      let(:previous_requirements) do
        [{
          file: "package.json",
          requirement: "^7.3.0",
          groups: ["Dependencies"],
          source: nil
        }]
      end

      let(:project_name) { "pnpm/unexpected_store" }

      it "raises a helpful error" do
        expect { updated_pnpm_lock_content }
          .to raise_error(Dependabot::DependencyFileNotResolvable)
      end
    end

    context "with a dependency resolution that returns unmet peer deps response" do
      let(:dependency_name) { "clsx" }
      let(:version) { "2.2.2" }
      let(:previous_version) { "^2.1.1" }
      let(:requirements) do
        [{
          file: "package.json",
          requirement: "^2.1.1",
          groups: ["peerDependencies"],
          source: nil
        }]
      end
      let(:previous_requirements) do
        [{
          file: "package.json",
          requirement: "2.2.2",
          groups: ["peerDependencies"],
          source: nil
        }]
      end

      let(:project_name) { "pnpm/unmet_peer_deps" }

      it "raises a helpful error" do
        expect { updated_pnpm_lock_content }
          .to raise_error(Dependabot::DependencyFileNotResolvable)
      end
    end
  end
end
