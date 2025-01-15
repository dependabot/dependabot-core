# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/npm_and_yarn/file_updater/bun_lockfile_updater"

RSpec.describe Dependabot::NpmAndYarn::FileUpdater::BunLockfileUpdater do
  subject(:updated_bun_lock_content) { updater.updated_bun_lock_content(bun_lock) }

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

  let(:bun_lock) do
    files.find { |f| f.name == "bun.lock" }
  end

  let(:tmp_path) { Dependabot::Utils::BUMP_TMP_DIR_PATH }

  let(:repo_contents_path) { build_tmp_repo(project_name, path: "projects") }

  before do
    FileUtils.mkdir_p(tmp_path)
    allow(Dependabot::Experiments).to receive(:enabled?)
      .with(:enable_shared_helpers_command_timeout).and_return(true)
  end

  after do
    Dependabot::Experiments.reset!
  end

  describe "errors" do
    context "without dependencies" do
      let(:project_name) { "bun/empty" }

      it "raises a helpful error" do
        expect { updated_bun_lock_content }
          .to raise_error("Expected content to change!")
      end
    end

    context "with an invalid lockfile" do
      let(:project_name) { "bun/invalid_lockfile" }

      it "raises a helpful error" do
        expect { updated_bun_lock_content }
          .to raise_error(Dependabot::DependencyFileNotParseable)
      end
    end

    context "with an invalid lockfile version" do
      let(:project_name) { "bun/invalid_lockfile_version" }

      it "raises a helpful error" do
        expect { updated_bun_lock_content }
          .to raise_error(Dependabot::DependencyFileNotParseable)
      end
    end

    context "with a dependency that is missing" do
      let(:project_name) { "bun/missing_dependency" }

      it "raises a helpful error" do
        expect { updated_bun_lock_content }
          .to raise_error(Dependabot::DependencyNotFound)
      end
    end

    context "with a dependency version that is missing" do
      let(:project_name) { "bun/missing_dependency_version" }

      it "raises a helpful error" do
        expect { updated_bun_lock_content }
          .to raise_error(Dependabot::DependencyFileNotResolvable)
      end
    end

    context "with a git dependency that is missing" do
      let(:project_name) { "bun/missing_git_dependency" }

      it "raises a helpful error" do
        expect { updated_bun_lock_content }
          .to raise_error(Dependabot::DependencyNotFound)
      end
    end

    context "with a github dependency that is missing" do
      let(:project_name) { "bun/missing_github_dependency" }

      it "raises a helpful error" do
        expect { updated_bun_lock_content }
          .to raise_error(Dependabot::DependencyNotFound)
      end
    end

    context "with a tarball dependency that is missing" do
      let(:project_name) { "bun/missing_tarball_dependency" }

      it "raises a helpful error" do
        expect { updated_bun_lock_content }
          .to raise_error(Dependabot::DependencyNotFound)
      end
    end

    context "with a npm dependency that is missing" do
      let(:project_name) { "bun/missing_npm_dependency" }

      it "raises a helpful error" do
        expect { updated_bun_lock_content }
          .to raise_error(Dependabot::DependencyNotFound)
      end
    end

    context "with a file dependency that is missing" do
      let(:project_name) { "bun/missing_file_dependency" }

      it "raises a helpful error" do
        expect { updated_bun_lock_content }
          .to raise_error(Dependabot::DependencyNotFound)
      end
    end
  end
end
