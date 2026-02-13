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
        let(:config_file_body) do
          <<~YAML
            repos:
              - repo: https://github.com/pre-commit/pre-commit-hooks
                rev: v4.4.0  # This is a comment
                hooks:
                  - id: trailing-whitespace
          YAML
        end

        its(:content) do
          is_expected.to include "rev: v4.5.0  # This is a comment"
          is_expected.not_to include "rev: v4.4.0"
        end
      end

      context "with multiple repos using the same ref value" do
        let(:config_file_body) do
          <<~YAML
            repos:
              - repo: https://github.com/pre-commit/pre-commit-hooks
                rev: v4.4.0
                hooks:
                  - id: trailing-whitespace
              - repo: https://github.com/psf/black
                rev: v4.4.0
                hooks:
                  - id: black
          YAML
        end

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
    end
  end
end
