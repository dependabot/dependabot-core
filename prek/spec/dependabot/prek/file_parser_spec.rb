# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency_file"
require "dependabot/prek/file_parser"
require_common_spec "file_parsers/shared_examples_for_file_parsers"

RSpec.describe Dependabot::Prek::FileParser do
  let(:files) { [prek_config] }
  let(:prek_config) do
    Dependabot::DependencyFile.new(
      name: "prek.toml",
      content: fixture("prek_configs", "basic.toml")
    )
  end
  let(:source) do
    Dependabot::Source.new(
      provider: "github",
      repo: "example/repo",
      directory: "/"
    )
  end
  let(:parser) do
    described_class.new(
      dependency_files: files,
      source: source
    )
  end

  it_behaves_like "a dependency file parser"

  describe "#ecosystem" do
    it "is named prek" do
      expect(parser.ecosystem.name).to eq("prek")
    end
  end

  describe "#parse" do
    subject(:dependencies) { parser.parse }

    it "returns one dependency per remote repo" do
      expect(dependencies.length).to eq(2)
    end

    it "parses a remote repo into a prek git dependency" do
      dep = dependencies.find { |d| d.name.include?("pre-commit-hooks") }
      expect(dep).not_to be_nil
      expect(dep.name).to eq("https://github.com/pre-commit/pre-commit-hooks")
      expect(dep.version).to eq("v4.4.0")
      expect(dep.package_manager).to eq("prek")
      expect(dep.requirements).to eq(
        [{
          requirement: nil,
          groups: [],
          file: "prek.toml",
          source: {
            type: "git",
            url: "https://github.com/pre-commit/pre-commit-hooks",
            ref: "v4.4.0",
            branch: nil
          },
          metadata: { comment: nil }
        }]
      )
    end

    it "parses a numeric-versioned repo correctly" do
      dep = dependencies.find { |d| d.name.include?("black") }
      expect(dep.version).to eq("23.12.1")
      expect(dep.requirements.first[:source][:ref]).to eq("23.12.1")
    end

    context "with version comments" do
      let(:prek_config) do
        Dependabot::DependencyFile.new(
          name: "prek.toml",
          content: fixture("prek_configs", "with_version_comments.toml")
        )
      end

      it "extracts a frozen comment from a SHA-pinned repo" do
        dep = dependencies.find { |d| d.name.include?("pre-commit-hooks") }
        expect(dep.requirements.first[:metadata][:comment]).to eq("# frozen: v4.4.0")
      end

      it "extracts a plain version comment from a SHA-pinned repo" do
        dep = dependencies.find { |d| d.name.include?("black") }
        expect(dep.requirements.first[:metadata][:comment]).to eq("# v23.12.1")
      end

      it "extracts a frozen comment from a tag-pinned repo" do
        dep = dependencies.find { |d| d.name.include?("flake8") }
        expect(dep.requirements.first[:metadata][:comment]).to eq("# frozen: v6.1.0")
      end

      it "returns a nil comment when no inline comment exists" do
        dep = dependencies.find { |d| d.name.include?("mirrors-mypy") }
        expect(dep.requirements.first[:metadata][:comment]).to be_nil
      end
    end

    context "with a frozen comment on an inline-table repo" do
      let(:prek_config) do
        Dependabot::DependencyFile.new(
          name: "prek.toml",
          content: fixture("prek_configs", "inline_frozen.toml")
        )
      end

      it "extracts the comment from the inline-table form" do
        dep = dependencies.find { |d| d.name.include?("pre-commit-hooks") }
        expect(dep.requirements.first[:metadata][:comment]).to eq("# frozen: v4.4.0")
      end
    end

    context "with a local repo" do
      let(:prek_config) do
        Dependabot::DependencyFile.new(
          name: "prek.toml",
          content: fixture("prek_configs", "with_local_repo.toml")
        )
      end

      it "skips the local repo" do
        expect(dependencies.map(&:name))
          .to eq(["https://github.com/pre-commit/pre-commit-hooks"])
      end
    end

    context "when a repo is missing a rev" do
      let(:prek_config) do
        Dependabot::DependencyFile.new(
          name: "prek.toml",
          content: fixture("prek_configs", "missing_rev.toml")
        )
      end

      it "skips repos without a rev" do
        expect(dependencies).to be_empty
      end
    end

    context "with invalid TOML" do
      let(:prek_config) do
        Dependabot::DependencyFile.new(
          name: "prek.toml",
          content: "= = not valid toml [[["
        )
      end

      it "raises a DependencyFileNotParseable error" do
        expect { dependencies }.to raise_error(Dependabot::DependencyFileNotParseable)
      end
    end

    context "with a duplicate key" do
      let(:prek_config) do
        Dependabot::DependencyFile.new(
          name: "prek.toml",
          content: <<~TOML
            [[repos]]
            repo = "https://github.com/pre-commit/pre-commit-hooks"
            rev = "v4.4.0"
            rev = "v5.0.0"
          TOML
        )
      end

      it "raises a DependencyFileNotParseable error" do
        expect { dependencies }.to raise_error(Dependabot::DependencyFileNotParseable)
      end
    end
  end
end
