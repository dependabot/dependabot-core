# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency"
require "dependabot/dependency_file"
require "dependabot/crystal_shards/file_updater/lockfile_updater"

RSpec.describe Dependabot::CrystalShards::FileUpdater::LockfileUpdater do
  describe "security validation" do
    let(:updater) do
      described_class.new(
        dependencies: [dependency],
        dependency_files: [shard_yml],
        credentials: []
      )
    end

    let(:dependency) do
      Dependabot::Dependency.new(
        name: "kemal",
        version: "1.1.0",
        previous_version: "1.0.0",
        requirements: [{
          file: "shard.yml",
          requirement: "~> 1.1.0",
          groups: ["dependencies"],
          source: { type: "git", url: "https://github.com/kemalcr/kemal" }
        }],
        previous_requirements: [{
          file: "shard.yml",
          requirement: "~> 1.0.0",
          groups: ["dependencies"],
          source: { type: "git", url: "https://github.com/kemalcr/kemal" }
        }],
        package_manager: "crystal_shards"
      )
    end

    describe "git URL validation" do
      context "with HTTP protocol" do
        let(:shard_yml) do
          Dependabot::DependencyFile.new(
            name: "shard.yml",
            content: <<~YAML
              name: test
              version: 1.0.0
              dependencies:
                evil:
                  git: http://github.com/evil/repo
            YAML
          )
        end

        it "rejects non-HTTPS URLs" do
          expect { updater.updated_lockfile_content }
            .to raise_error(Dependabot::DependencyFileNotResolvable, /must use HTTPS/)
        end
      end

      context "with disallowed host" do
        let(:shard_yml) do
          Dependabot::DependencyFile.new(
            name: "shard.yml",
            content: <<~YAML
              name: test
              version: 1.0.0
              dependencies:
                evil:
                  git: https://evil.com/malicious/repo.git
            YAML
          )
        end

        it "rejects URLs from non-allowed hosts" do
          expect { updater.updated_lockfile_content }
            .to raise_error(Dependabot::DependencyFileNotResolvable, /unsupported host/)
        end
      end

      context "with query parameters" do
        let(:shard_yml) do
          Dependabot::DependencyFile.new(
            name: "shard.yml",
            content: <<~YAML
              name: test
              version: 1.0.0
              dependencies:
                evil:
                  git: https://github.com/evil/repo.git?malicious=param
            YAML
          )
        end

        it "rejects URLs with query parameters" do
          expect { updater.updated_lockfile_content }
            .to raise_error(Dependabot::DependencyFileNotResolvable, %r{query/fragment not allowed})
        end
      end

      context "with shell metacharacters" do
        let(:shard_yml) do
          Dependabot::DependencyFile.new(
            name: "shard.yml",
            content: <<~YAML
              name: test
              version: 1.0.0
              dependencies:
                evil:
                  git: https://github.com/evil/repo;rm -rf /
            YAML
          )
        end

        it "rejects URLs with dangerous characters" do
          expect { updater.updated_lockfile_content }
            .to raise_error(Dependabot::DependencyFileNotResolvable, /invalid git URL/)
        end
      end
    end

    describe "path dependency validation" do
      context "with path traversal" do
        let(:shard_yml) do
          Dependabot::DependencyFile.new(
            name: "shard.yml",
            content: <<~YAML
              name: test
              version: 1.0.0
              dependencies:
                evil:
                  path: ../../../etc/passwd
            YAML
          )
        end

        it "rejects path traversal attempts" do
          expect { updater.updated_lockfile_content }
            .to raise_error(Dependabot::DependencyFileNotResolvable, /unsafe path/)
        end
      end

      context "with absolute path" do
        let(:shard_yml) do
          Dependabot::DependencyFile.new(
            name: "shard.yml",
            content: <<~YAML
              name: test
              version: 1.0.0
              dependencies:
                evil:
                  path: /etc/passwd
            YAML
          )
        end

        it "rejects absolute paths" do
          expect { updater.updated_lockfile_content }
            .to raise_error(Dependabot::DependencyFileNotResolvable, /unsafe path/)
        end
      end
    end

    describe "shorthand validation" do
      context "with invalid github shorthand" do
        let(:shard_yml) do
          Dependabot::DependencyFile.new(
            name: "shard.yml",
            content: <<~YAML
              name: test
              version: 1.0.0
              dependencies:
                evil:
                  github: ../../../etc/passwd
            YAML
          )
        end

        it "rejects invalid shorthand format" do
          expect { updater.updated_lockfile_content }
            .to raise_error(Dependabot::DependencyFileNotResolvable, /invalid.*shorthand/)
        end
      end
    end

    describe "file size validation" do
      context "with oversized manifest" do
        let(:shard_yml) do
          Dependabot::DependencyFile.new(
            name: "shard.yml",
            content: "name: test\n" + ("x" * 2_000_000)
          )
        end

        it "rejects files exceeding size limit" do
          expect { updater.updated_lockfile_content }
            .to raise_error(Dependabot::DependencyFileNotParseable, /too large/)
        end
      end
    end
  end
end
