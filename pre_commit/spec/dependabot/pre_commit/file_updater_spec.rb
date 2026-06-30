# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency"
require "dependabot/dependency_file"
require "dependabot/source"
require "dependabot/pre_commit/file_updater"
require "dependabot/pre_commit/version"
require_common_spec "file_updaters/shared_examples_for_file_updaters"

RSpec.describe Dependabot::PreCommit::FileUpdater do
  let(:dependency) do
    Dependabot::Dependency.new(
      name: "https://github.com/pre-commit/pre-commit-hooks",
      version: "v4.5.0",
      previous_version: "v4.4.0",
      requirements: [{
        requirement: nil,
        groups: [],
        file: ".pre-commit-config.yaml",
        source: {
          type: "git",
          url: "https://github.com/pre-commit/pre-commit-hooks",
          ref: "v4.5.0",
          branch: nil
        }
      }],
      previous_requirements: [{
        requirement: nil,
        groups: [],
        file: ".pre-commit-config.yaml",
        source: {
          type: "git",
          url: "https://github.com/pre-commit/pre-commit-hooks",
          ref: "v4.4.0",
          branch: nil
        }
      }],
      package_manager: "pre_commit"
    )
  end
  let(:config_file_body) { fixture("pre_commit_configs", "basic.yaml") }
  let(:config_file) do
    Dependabot::DependencyFile.new(
      content: config_file_body,
      name: ".pre-commit-config.yaml"
    )
  end
  let(:credentials) do
    [{
      "type" => "git_source",
      "host" => "github.com",
      "username" => "x-access-token",
      "password" => "token"
    }]
  end
  let(:files) { [config_file] }
  let(:updater) do
    described_class.new(
      dependency_files: files,
      dependencies: [dependency],
      credentials: credentials
    )
  end

  it_behaves_like "a dependency file updater"

  describe "#updated_dependency_files" do
    subject(:updated_files) { updater.updated_dependency_files }

    it "returns DependencyFile objects" do
      expect(updated_files).to all(be_a(Dependabot::DependencyFile))
    end

    its(:length) { is_expected.to eq(1) }

    describe "the updated config file" do
      subject(:updated_config_file) do
        updated_files.find { |f| f.name == ".pre-commit-config.yaml" }
      end

      its(:content) do
        is_expected.to include "rev: v4.5.0"
        is_expected.not_to include "rev: v4.4.0"
      end

      context "with a commit SHA" do
        let(:dependency) do
          Dependabot::Dependency.new(
            name: "https://github.com/pycqa/flake8",
            version: "abc123def456",
            previous_version: "6f6a02c2c85a1b45e39c1aa5e6cc40f7a3d6df5e",
            requirements: [{
              requirement: nil,
              groups: [],
              file: ".pre-commit-config.yaml",
              source: {
                type: "git",
                url: "https://github.com/pycqa/flake8",
                ref: "abc123def456",
                branch: nil
              }
            }],
            previous_requirements: [{
              requirement: nil,
              groups: [],
              file: ".pre-commit-config.yaml",
              source: {
                type: "git",
                url: "https://github.com/pycqa/flake8",
                ref: "6f6a02c2c85a1b45e39c1aa5e6cc40f7a3d6df5e",
                branch: nil
              }
            }],
            package_manager: "pre_commit"
          )
        end
        let(:config_file_body) { fixture("pre_commit_configs", "with_hashes_and_tags.yaml") }

        its(:content) do
          is_expected.to include "rev: abc123def456"
          is_expected.not_to include "rev: 6f6a02c2c85a1b45e39c1aa5e6cc40f7a3d6df5e"
        end
      end

      context "with inline comments" do
        let(:config_file_body) { fixture("pre_commit_configs", "with_inline_comment.yaml") }

        its(:content) do
          is_expected.to include "rev: v4.5.0  # This is a comment"
          is_expected.not_to include "rev: v4.4.0"
        end
      end

      context "with SHA ref and frozen version comment" do
        let(:dependency) do
          Dependabot::Dependency.new(
            name: "https://github.com/pre-commit/pre-commit-hooks",
            version: "def456abc789def456abc789def456abc789def456",
            previous_version: "6f6a02c2c85a1b45e39c1aa5e6cc40f7a3d6df5e",
            requirements: [{
              requirement: nil,
              groups: [],
              file: ".pre-commit-config.yaml",
              source: {
                type: "git",
                url: "https://github.com/pre-commit/pre-commit-hooks",
                ref: "def456abc789def456abc789def456abc789def456",
                branch: nil
              },
              metadata: { comment_version: "v4.4.0", new_comment_version: "v6.0.0" }
            }],
            previous_requirements: [{
              requirement: nil,
              groups: [],
              file: ".pre-commit-config.yaml",
              source: {
                type: "git",
                url: "https://github.com/pre-commit/pre-commit-hooks",
                ref: "6f6a02c2c85a1b45e39c1aa5e6cc40f7a3d6df5e",
                branch: nil
              },
              metadata: { comment: "# frozen: v4.4.0" }
            }],
            package_manager: "pre_commit"
          )
        end
        let(:config_file_body) { fixture("pre_commit_configs", "with_frozen_version_comment.yaml") }

        it "updates both the SHA and the version in the comment" do
          expect(updated_config_file.content)
            .to include "rev: def456abc789def456abc789def456abc789def456  # frozen: v6.0.0"
          expect(updated_config_file.content)
            .not_to include "6f6a02c2c85a1b45e39c1aa5e6cc40f7a3d6df5e"
          expect(updated_config_file.content)
            .not_to include "v4.4.0"
        end
      end

      context "with SHA ref and plain version comment" do
        let(:dependency) do
          Dependabot::Dependency.new(
            name: "https://github.com/pre-commit/pre-commit-hooks",
            version: "def456abc789def456abc789def456abc789def456",
            previous_version: "6f6a02c2c85a1b45e39c1aa5e6cc40f7a3d6df5e",
            requirements: [{
              requirement: nil,
              groups: [],
              file: ".pre-commit-config.yaml",
              source: {
                type: "git",
                url: "https://github.com/pre-commit/pre-commit-hooks",
                ref: "def456abc789def456abc789def456abc789def456",
                branch: nil
              },
              metadata: { comment_version: "v4.4.0", new_comment_version: "v6.0.0" }
            }],
            previous_requirements: [{
              requirement: nil,
              groups: [],
              file: ".pre-commit-config.yaml",
              source: {
                type: "git",
                url: "https://github.com/pre-commit/pre-commit-hooks",
                ref: "6f6a02c2c85a1b45e39c1aa5e6cc40f7a3d6df5e",
                branch: nil
              },
              metadata: { comment: "# v4.4.0" }
            }],
            package_manager: "pre_commit"
          )
        end
        let(:config_file_body) { fixture("pre_commit_configs", "with_plain_version_comment.yaml") }

        it "updates both the SHA and the version in the comment" do
          expect(updated_config_file.content)
            .to include "rev: def456abc789def456abc789def456abc789def456  # v6.0.0"
        end
      end

      context "with multiple repos using the same ref value" do
        let(:config_file_body) { fixture("pre_commit_configs", "with_multiple_repos_same_ref.yaml") }

        its(:content) do
          is_expected.to include "- repo: https://github.com/pre-commit/pre-commit-hooks"
          is_expected.to include "  rev: v4.5.0"
          is_expected.to include "- repo: https://github.com/psf/black"
          is_expected.to include "  rev: v4.4.0"
        end

        it "only updates the intended repo's rev field" do
          content = updated_config_file.content
          pre_commit_hooks_section = content[
            %r{- repo: https://github\.com/pre-commit/pre-commit-hooks.*?(?=- repo:|\z)}m
          ]
          black_section = content[
            %r{- repo: https://github\.com/psf/black.*?(?=- repo:|\z)}m
          ]

          expect(pre_commit_hooks_section).to include("rev: v4.5.0")
          expect(pre_commit_hooks_section).not_to include("rev: v4.4.0")
          expect(black_section).to include("rev: v4.4.0")
          expect(black_section).not_to include("rev: v4.5.0")
        end
      end

      context "with same repo used multiple times with different revs" do
        let(:dependency) do
          Dependabot::Dependency.new(
            name: "https://github.com/pre-commit/pre-commit-hooks",
            version: "v4.6.0",
            previous_version: "v4.4.0",
            requirements: [{
              requirement: nil,
              groups: [],
              file: ".pre-commit-config.yaml",
              source: {
                type: "git",
                url: "https://github.com/pre-commit/pre-commit-hooks",
                ref: "v4.6.0",
                branch: nil
              }
            }],
            previous_requirements: [{
              requirement: nil,
              groups: [],
              file: ".pre-commit-config.yaml",
              source: {
                type: "git",
                url: "https://github.com/pre-commit/pre-commit-hooks",
                ref: "v4.4.0",
                branch: nil
              }
            }],
            package_manager: "pre_commit"
          )
        end
        let(:config_file_body) { fixture("pre_commit_configs", "same_repo_different_revs.yaml") }

        it "only updates the occurrence that matches both repo URL and old ref" do
          content = updated_config_file.content
          lines = content.lines

          # Find the first occurrence of the repo with v4.4.0 (should be updated to v4.6.0)
          first_repo_idx = lines.index { |l| l.include?("repo: https://github.com/pre-commit/pre-commit-hooks") }
          first_rev_idx = lines[first_repo_idx..].index { |l| l.match?(/^\s*rev:/) }
          first_rev_line = lines[first_repo_idx + first_rev_idx]

          # Find the second occurrence of the repo with v4.5.0 (should remain unchanged)
          second_repo_idx = lines[(first_repo_idx + 1)..].index do |l|
            l.include?("repo: https://github.com/pre-commit/pre-commit-hooks")
          end
          second_rev_idx = lines[(first_repo_idx + 1 + second_repo_idx)..].index { |l| l.match?(/^\s*rev:/) }
          second_rev_line = lines[first_repo_idx + 1 + second_repo_idx + second_rev_idx]

          expect(first_rev_line).to include("v4.6.0")
          expect(second_rev_line).to include("v4.5.0")
        end
      end

      context "with quoted repo URLs" do
        let(:config_file_body) { fixture("pre_commit_configs", "with_quoted_urls.yaml") }

        its(:content) do
          is_expected.to include "rev: v4.5.0"
          is_expected.not_to include "rev: v4.4.0"
        end

        it "updates the rev even when repo URL is double-quoted" do
          expect(updated_config_file.content).to include('- repo: "https://github.com/pre-commit/pre-commit-hooks"')
          expect(updated_config_file.content).to include("rev: v4.5.0")
        end
      end

      context "with single-quoted rev values" do
        let(:config_file_body) { fixture("pre_commit_configs", "with_quoted_revs.yaml") }

        it "updates the rev and preserves the single quotes" do
          expect(updated_config_file.content).to include "rev: 'v4.5.0'"
          expect(updated_config_file.content).not_to include "rev: 'v4.4.0'"
        end

        it "does not modify other repos" do
          expect(updated_config_file.content).to include 'rev: "23.12.1"'
        end
      end

      context "with double-quoted rev values" do
        let(:dependency) do
          Dependabot::Dependency.new(
            name: "https://github.com/psf/black",
            version: "24.1.0",
            previous_version: "23.12.1",
            requirements: [{
              requirement: nil,
              groups: [],
              file: ".pre-commit-config.yaml",
              source: {
                type: "git",
                url: "https://github.com/psf/black",
                ref: "24.1.0",
                branch: nil
              }
            }],
            previous_requirements: [{
              requirement: nil,
              groups: [],
              file: ".pre-commit-config.yaml",
              source: {
                type: "git",
                url: "https://github.com/psf/black",
                ref: "23.12.1",
                branch: nil
              }
            }],
            package_manager: "pre_commit"
          )
        end
        let(:config_file_body) { fixture("pre_commit_configs", "with_quoted_revs.yaml") }

        it "updates the rev and preserves the double quotes" do
          expect(updated_config_file.content).to include 'rev: "24.1.0"'
          expect(updated_config_file.content).not_to include 'rev: "23.12.1"'
        end

        it "does not modify other repos" do
          expect(updated_config_file.content).to include "rev: 'v4.4.0'"
        end
      end
    end

    context "with a prek.toml (TOML) config" do
      let(:dependency) do
        Dependabot::Dependency.new(
          name: "https://github.com/pre-commit/pre-commit-hooks",
          version: "v6.0.0",
          previous_version: "v4.4.0",
          requirements: [{
            requirement: nil, groups: [], file: "prek.toml",
            source: {
              type: "git", url: "https://github.com/pre-commit/pre-commit-hooks", ref: "v6.0.0", branch: nil
            }
          }],
          previous_requirements: [{
            requirement: nil, groups: [], file: "prek.toml",
            source: {
              type: "git", url: "https://github.com/pre-commit/pre-commit-hooks", ref: "v4.4.0", branch: nil
            }
          }],
          package_manager: "pre_commit"
        )
      end
      let(:config_file_body) { fixture("prek_configs", "basic.toml") }
      let(:config_file) do
        Dependabot::DependencyFile.new(content: config_file_body, name: "prek.toml")
      end

      describe "the updated config file" do
        subject(:updated_config_file) do
          updated_files.find { |f| f.name == "prek.toml" }
        end

        its(:content) do
          is_expected.to include 'rev = "v6.0.0"'
          is_expected.not_to include 'rev = "v4.4.0"'
        end

        it "leaves other repos untouched" do
          expect(updated_config_file.content).to include 'rev = "23.12.1"'
        end
      end

      context "when only a different repo is updated" do
        let(:dependency) do
          Dependabot::Dependency.new(
            name: "https://github.com/psf/black",
            version: "24.0.0",
            previous_version: "23.12.1",
            requirements: [{
              requirement: nil, groups: [], file: "prek.toml",
              source: {
                type: "git", url: "https://github.com/psf/black", ref: "24.0.0", branch: nil
              }
            }],
            previous_requirements: [{
              requirement: nil, groups: [], file: "prek.toml",
              source: {
                type: "git", url: "https://github.com/psf/black", ref: "23.12.1", branch: nil
              }
            }],
            package_manager: "pre_commit"
          )
        end

        it "updates only the matching repo's rev" do
          content = updated_files.find { |f| f.name == "prek.toml" }.content
          expect(content).to include 'rev = "24.0.0"'
          expect(content).to include 'rev = "v4.4.0"'
        end
      end

      context "with repos defined as an inline-table array" do
        let(:config_file_body) { fixture("prek_configs", "inline_repos.toml") }

        it "updates the rev inside the matching inline table" do
          content = updated_files.find { |f| f.name == "prek.toml" }.content
          expect(content).to include 'rev = "v6.0.0"'
          expect(content).not_to include 'rev = "v4.4.0"'
        end

        it "leaves other inline-table repos untouched" do
          content = updated_files.find { |f| f.name == "prek.toml" }.content
          expect(content).to include 'rev = "23.12.1"'
        end
      end

      context "with a frozen SHA pin and version comment" do
        let(:config_file_body) { fixture("prek_configs", "frozen.toml") }
        let(:dependency) do
          Dependabot::Dependency.new(
            name: "https://github.com/pre-commit/pre-commit-hooks",
            version: "10864545ddc58bd96330029b6bff16da3d072237",
            previous_version: "6f6a02c2c85a1b45e39c1aa5e6cc40f7a3d6df5e",
            requirements: [{
              requirement: nil, groups: [], file: "prek.toml",
              source: {
                type: "git", url: "https://github.com/pre-commit/pre-commit-hooks",
                ref: "10864545ddc58bd96330029b6bff16da3d072237", branch: nil
              },
              metadata: { comment_version: "v4.4.0", new_comment_version: "v6.0.0" }
            }],
            previous_requirements: [{
              requirement: nil, groups: [], file: "prek.toml",
              source: {
                type: "git", url: "https://github.com/pre-commit/pre-commit-hooks",
                ref: "6f6a02c2c85a1b45e39c1aa5e6cc40f7a3d6df5e", branch: nil
              },
              metadata: { comment: "# frozen: v4.4.0" }
            }],
            package_manager: "pre_commit"
          )
        end

        it "rewrites both the SHA and the frozen version comment" do
          content = updated_files.find { |f| f.name == "prek.toml" }.content
          expect(content).to include('rev = "10864545ddc58bd96330029b6bff16da3d072237"')
          expect(content).to include("# frozen: v6.0.0")
          expect(content).not_to include("6f6a02c2c85a1b45e39c1aa5e6cc40f7a3d6df5e")
          expect(content).not_to include("v4.4.0")
        end
      end

      context "when the dependency's old ref is a prefix of the on-file rev" do
        # The on-file rev is "v4.4.0"; the recorded previous ref is the prefix
        # "v4.4". A prefix must NOT partially rewrite the longer on-file value.
        let(:dependency) do
          Dependabot::Dependency.new(
            name: "https://github.com/pre-commit/pre-commit-hooks",
            version: "v6.0.0",
            previous_version: "v4.4",
            requirements: [{
              requirement: nil, groups: [], file: "prek.toml",
              source: {
                type: "git", url: "https://github.com/pre-commit/pre-commit-hooks", ref: "v6.0.0", branch: nil
              }
            }],
            previous_requirements: [{
              requirement: nil, groups: [], file: "prek.toml",
              source: {
                type: "git", url: "https://github.com/pre-commit/pre-commit-hooks", ref: "v4.4", branch: nil
              }
            }],
            package_manager: "pre_commit"
          )
        end

        it "does not corrupt the longer rev value" do
          expect { updated_files }.to raise_error(/No files changed/)
        end
      end

      context "when a later table's rev precedes its repo" do
        # Both tables pin the same rev value, and the second table lists `rev`
        # before `repo` (legal TOML). A leaked current_repo would rewrite the
        # second table's rev too; the [[repos]]-header reset prevents that.
        let(:config_file_body) { fixture("prek_configs", "rev_before_repo.toml") }

        it "rewrites only the targeted repo's rev" do
          content = updated_files.find { |f| f.name == "prek.toml" }.content
          expect(content.scan('rev = "v6.0.0"').length).to eq(1)
          # The second table (psf/black) keeps its rev untouched.
          expect(content).to include('rev = "v4.4.0"  # frozen: v4.4.0')
        end
      end
    end
  end
end
