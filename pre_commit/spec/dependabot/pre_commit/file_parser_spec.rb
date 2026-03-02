# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency_file"
require "dependabot/pre_commit/file_parser"
require_common_spec "file_parsers/shared_examples_for_file_parsers"

RSpec.describe Dependabot::PreCommit::FileParser do
  let(:files) { [pre_commit_config] }
  let(:pre_commit_config) do
    Dependabot::DependencyFile.new(
      name: ".pre-commit-config.yaml",
      content: fixture("pre_commit_configs", "basic.yaml")
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

  describe "#parse" do
    subject(:dependencies) { parser.parse }

    it "returns the correct number of dependencies" do
      expect(dependencies.length).to eq(2)
    end

    it "parses the first dependency correctly" do
      dep = dependencies.find { |d| d.name.include?("pre-commit-hooks") }
      expect(dep).not_to be_nil
      expect(dep.name).to eq("https://github.com/pre-commit/pre-commit-hooks")
      expect(dep.version).to eq("v4.4.0")
      expect(dep.requirements).to eq(
        [{
          requirement: nil,
          groups: [],
          file: ".pre-commit-config.yaml",
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

    it "parses the second dependency correctly" do
      dep = dependencies.find { |d| d.name.include?("black") }
      expect(dep).not_to be_nil
      expect(dep.name).to eq("https://github.com/psf/black")
      expect(dep.version).to eq("23.12.1")
    end

    context "with hashes and tags" do
      let(:pre_commit_config) do
        Dependabot::DependencyFile.new(
          name: ".pre-commit-config.yaml",
          content: fixture("pre_commit_configs", "with_hashes_and_tags.yaml")
        )
      end

      it "returns the correct number of dependencies" do
        expect(dependencies.length).to eq(4)
      end

      it "parses a semver tag correctly" do
        dep = dependencies.find { |d| d.name.include?("pre-commit-hooks") }
        expect(dep.version).to eq("v4.4.0")
        expect(dep.requirements.first[:source][:ref]).to eq("v4.4.0")
      end

      it "parses a numeric version correctly" do
        dep = dependencies.find { |d| d.name.include?("black") }
        expect(dep.version).to eq("23.12.1")
        expect(dep.requirements.first[:source][:ref]).to eq("23.12.1")
      end

      it "parses a full commit SHA correctly" do
        dep = dependencies.find { |d| d.name.include?("flake8") }
        expect(dep.version).to eq("6f6a02c2c85a1b45e39c1aa5e6cc40f7a3d6df5e")
        expect(dep.requirements.first[:source][:ref]).to eq("6f6a02c2c85a1b45e39c1aa5e6cc40f7a3d6df5e")
      end

      it "parses a short commit SHA correctly" do
        dep = dependencies.find { |d| d.name.include?("mypy") }
        expect(dep.version).to eq("a1b2c3d")
        expect(dep.requirements.first[:source][:ref]).to eq("a1b2c3d")
      end
    end

    context "with version comments" do
      let(:pre_commit_config) do
        Dependabot::DependencyFile.new(
          name: ".pre-commit-config.yaml",
          content: fixture("pre_commit_configs", "with_version_comments.yaml")
        )
      end

      it "returns the correct number of dependencies" do
        expect(dependencies.length).to eq(4)
      end

      it "extracts frozen comment from SHA-pinned repo" do
        dep = dependencies.find { |d| d.name.include?("pre-commit-hooks") }
        expect(dep.requirements.first[:metadata][:comment]).to eq("# frozen: v4.4.0")
      end

      it "extracts plain version comment from SHA-pinned repo" do
        dep = dependencies.find { |d| d.name.include?("black") }
        expect(dep.requirements.first[:metadata][:comment]).to eq("# v23.12.1")
      end

      it "extracts frozen comment from tag-pinned repo" do
        dep = dependencies.find { |d| d.name.include?("flake8") }
        expect(dep.requirements.first[:metadata][:comment]).to eq("# frozen: v6.1.0")
      end

      it "returns nil comment when no inline comment exists" do
        dep = dependencies.find { |d| d.name.include?("mypy") }
        expect(dep.requirements.first[:metadata][:comment]).to be_nil
      end
    end

    context "with local repos" do
      let(:pre_commit_config) do
        Dependabot::DependencyFile.new(
          name: ".pre-commit-config.yaml",
          content: fixture("pre_commit_configs", "with_local_repo.yaml")
        )
      end

      it "skips local repos" do
        expect(dependencies.length).to eq(1)
        expect(dependencies.first.name).to eq("https://github.com/pre-commit/pre-commit-hooks")
      end
    end

    context "with invalid YAML" do
      let(:pre_commit_config) do
        Dependabot::DependencyFile.new(
          name: ".pre-commit-config.yaml",
          content: fixture("pre_commit_configs", "invalid.yaml")
        )
      end

      it "raises a DependencyFileNotParseable error" do
        expect { dependencies }
          .to raise_error(Dependabot::DependencyFileNotParseable)
      end
    end

    context "with empty config" do
      let(:pre_commit_config) do
        Dependabot::DependencyFile.new(
          name: ".pre-commit-config.yaml",
          content: fixture("pre_commit_configs", "empty.yaml")
        )
      end

      it "returns an empty array" do
        expect(dependencies).to eq([])
      end
    end

    context "with repos missing rev" do
      let(:pre_commit_config) do
        Dependabot::DependencyFile.new(
          name: ".pre-commit-config.yaml",
          content: fixture("pre_commit_configs", "missing_rev.yaml")
        )
      end

      it "skips repos without rev" do
        expect(dependencies).to eq([])
      end
    end

    context "with python additional_dependencies" do
      let(:pre_commit_config) do
        Dependabot::DependencyFile.new(
          name: ".pre-commit-config.yaml",
          content: fixture("pre_commit_configs", "with_python_additional_dependencies.yaml")
        )
      end

      it "parses both repo and additional dependencies" do
        additional_deps, repo_deps = dependencies.partition do |d|
          d.requirements.first[:groups].include?("additional_dependencies")
        end

        expect(repo_deps.length).to eq(5)
        expect(additional_deps.length).to eq(12)
      end

      it "parses an exact-pinned additional dependency" do
        dep = dependencies.find { |d| d.name == "types-requests" }
        expect(dep).not_to be_nil
        expect(dep.version).to eq("2.31.0.1")
        expect(dep.requirements.first[:requirement]).to eq("==2.31.0.1")
        expect(dep.requirements.first[:source][:language]).to eq("python")
        expect(dep.requirements.first[:source][:package_name]).to eq("types-requests")
        expect(dep.requirements.first[:source][:hook_id]).to eq("mypy")
      end

      it "parses a lower-bound additional dependency" do
        dep = dependencies.find { |d| d.name == "types-pyyaml" }
        expect(dep).not_to be_nil
        expect(dep.version).to eq("6.0.0")
        expect(dep.requirements.first[:requirement]).to eq(">=6.0.0")
      end

      it "parses an additional dependency with extras" do
        dep = dependencies.find { |d| d.name == "black" }
        expect(dep).not_to be_nil
        expect(dep.version).to eq("23.0.0")
        expect(dep.requirements.first[:source][:extras]).to eq("d")
      end

      it "parses a compatible release (~=) additional dependency" do
        dep = dependencies.find { |d| d.name == "flake8-docstrings" }
        expect(dep).not_to be_nil
        expect(dep.version).to eq("1.7.0")
      end
    end

    context "with node additional_dependencies" do
      let(:pre_commit_config) do
        Dependabot::DependencyFile.new(
          name: ".pre-commit-config.yaml",
          content: fixture("pre_commit_configs", "with_node_additional_dependencies.yaml")
        )
      end

      it "parses both repo and additional dependencies" do
        additional_deps, repo_deps = dependencies.partition do |d|
          d.requirements.first[:groups].include?("additional_dependencies")
        end

        expect(repo_deps.length).to eq(4)
        expect(additional_deps.length).to eq(8)
      end

      it "parses a simple node additional dependency" do
        dep = dependencies.find { |d| d.name == "eslint" && d.requirements.first[:source][:hook_id] == "eslint" }
        expect(dep).not_to be_nil
        expect(dep.version).to eq("4.15.0")
        expect(dep.requirements.first[:requirement]).to eq("4.15.0")
        expect(dep.requirements.first[:source][:language]).to eq("node")
        expect(dep.requirements.first[:source][:package_name]).to eq("eslint")
        expect(dep.requirements.first[:source][:hook_id]).to eq("eslint")
        expect(dep.requirements.first[:source][:original_string]).to eq("eslint@4.15.0")
      end

      it "parses a scoped node additional dependency" do
        dep = dependencies.find { |d| d.name == "@prettier/plugin-xml" }
        expect(dep).not_to be_nil
        expect(dep.version).to eq("3.2.0")
        expect(dep.requirements.first[:requirement]).to eq("3.2.0")
        expect(dep.requirements.first[:source][:language]).to eq("node")
        expect(dep.requirements.first[:source][:original_string]).to eq("@prettier/plugin-xml@3.2.0")
      end

      it "parses a tilde-range node additional dependency" do
        dep = dependencies.find { |d| d.name == "typescript" }
        expect(dep).not_to be_nil
        expect(dep.version).to eq("5.3.0")
        expect(dep.requirements.first[:requirement]).to eq("~5.3.0")
      end

      it "parses a caret-range node additional dependency" do
        dep = dependencies.find { |d| d.name == "ts-node" }
        expect(dep).not_to be_nil
        expect(dep.version).to eq("10.9.0")
        expect(dep.requirements.first[:requirement]).to eq("^10.9.0")
      end
    end

    context "with golang additional_dependencies" do
      let(:pre_commit_config) do
        Dependabot::DependencyFile.new(
          name: ".pre-commit-config.yaml",
          content: fixture("pre_commit_configs", "with_go_additional_dependencies.yaml")
        )
      end

      it "parses both repo and additional dependencies" do
        additional_deps, repo_deps = dependencies.partition do |d|
          d.requirements.first[:groups].include?("additional_dependencies")
        end

        expect(repo_deps.length).to eq(2)
        expect(additional_deps.length).to eq(2)
      end

      it "parses a Go additional dependency with standard version" do
        dep = dependencies.find { |d| d.name == "golang.org/x/tools" }
        expect(dep).not_to be_nil
        expect(dep.version).to eq("0.28.0")
        expect(dep.requirements.first[:requirement]).to eq("v0.28.0")
        expect(dep.requirements.first[:source][:language]).to eq("golang")
        expect(dep.requirements.first[:source][:package_name]).to eq("golang.org/x/tools")
        expect(dep.requirements.first[:source][:hook_id]).to eq("golangci-lint")
        expect(dep.requirements.first[:source][:original_string]).to eq("golang.org/x/tools@v0.28.0")
      end

      it "parses a second Go additional dependency" do
        dep = dependencies.find { |d| d.name == "github.com/stretchr/testify" }
        expect(dep).not_to be_nil
        expect(dep.version).to eq("1.9.0")
        expect(dep.requirements.first[:requirement]).to eq("v1.9.0")
        expect(dep.requirements.first[:source][:original_string]).to eq("github.com/stretchr/testify@v1.9.0")
      end
    end

    context "with rust additional_dependencies" do
      let(:pre_commit_config) do
        Dependabot::DependencyFile.new(
          name: ".pre-commit-config.yaml",
          content: fixture("pre_commit_configs", "with_rust_additional_dependencies.yaml")
        )
      end

      it "parses a simple rust additional dependency" do
        dep = dependencies.find { |d| d.name == "serde" }
        expect(dep).not_to be_nil
        expect(dep.version).to eq("1.0.193")
        expect(dep.requirements.first[:requirement]).to eq("1.0.193")
        expect(dep.requirements.first[:source][:language]).to eq("rust")
        expect(dep.requirements.first[:source][:package_name]).to eq("serde")
        expect(dep.requirements.first[:source][:hook_id]).to eq("nickel-lint")
        expect(dep.requirements.first[:source][:original_string]).to eq("serde:1.0.193")
      end

      it "parses a CLI rust additional dependency" do
        dep = dependencies.find { |d| d.name == "rustfmt-nightly" }
        expect(dep).not_to be_nil
        expect(dep.version).to eq("1.6.0")
        expect(dep.requirements.first[:requirement]).to eq("1.6.0")
        expect(dep.requirements.first[:source][:extras]).to eq("cli")
        expect(dep.requirements.first[:source][:original_string]).to eq("cli:rustfmt-nightly:1.6.0")
      end

      it "parses a tilde-range rust additional dependency" do
        dep = dependencies.find { |d| d.name == "anyhow" }
        expect(dep).not_to be_nil
        expect(dep.version).to eq("1.0.0")
        expect(dep.requirements.first[:requirement]).to eq("~1.0.0")
      end

      it "parses a caret-range rust additional dependency" do
        dep = dependencies.find { |d| d.name == "clap" }
        expect(dep).not_to be_nil
        expect(dep.version).to eq("4.4.0")
        expect(dep.requirements.first[:requirement]).to eq("^4.4.0")
      end
    end

    context "with ruby additional_dependencies" do
      let(:pre_commit_config) do
        Dependabot::DependencyFile.new(
          name: ".pre-commit-config.yaml",
          content: fixture("pre_commit_configs", "with_ruby_additional_dependencies.yaml")
        )
      end

      it "parses both repo and additional dependencies" do
        additional_deps, repo_deps = dependencies.partition do |d|
          d.requirements.first[:groups].include?("additional_dependencies")
        end

        expect(repo_deps.length).to eq(3)
        expect(additional_deps.length).to eq(5)
      end

      it "parses a simple ruby additional dependency" do
        dep = dependencies.find { |d| d.name == "scss_lint" }
        expect(dep).not_to be_nil
        expect(dep.version).to eq("0.52.0")
        expect(dep.requirements.first[:requirement]).to eq("0.52.0")
        expect(dep.requirements.first[:source][:language]).to eq("ruby")
        expect(dep.requirements.first[:source][:package_name]).to eq("scss_lint")
        expect(dep.requirements.first[:source][:hook_id]).to eq("scss-lint")
        expect(dep.requirements.first[:source][:original_string]).to eq("scss_lint:0.52.0")
      end

      it "parses a pessimistic version ruby additional dependency" do
        dep = dependencies.find { |d| d.name == "rubocop" && d.requirements.first[:source][:hook_id] == "rubocop" }
        expect(dep).not_to be_nil
        expect(dep.version).to eq("1.50")
        expect(dep.requirements.first[:requirement]).to eq("~> 1.50")
        expect(dep.requirements.first[:source][:language]).to eq("ruby")
      end

      it "parses a hyphenated gem name" do
        dep = dependencies.find { |d| d.name == "rubocop-rails" }
        expect(dep).not_to be_nil
        expect(dep.version).to eq("2.19.0")
        expect(dep.requirements.first[:requirement]).to eq("2.19.0")
      end

      it "parses a >= constraint ruby additional dependency" do
        dep = dependencies.find { |d| d.name == "rubocop-performance" }
        expect(dep).not_to be_nil
        expect(dep.version).to eq("1.17.0")
        expect(dep.requirements.first[:requirement]).to eq(">= 1.17.0")
      end
    end

    context "with dart additional_dependencies" do
      let(:pre_commit_config) do
        Dependabot::DependencyFile.new(
          name: ".pre-commit-config.yaml",
          content: fixture("pre_commit_configs", "with_dart_additional_dependencies.yaml")
        )
      end

      it "parses both repo and additional dependencies" do
        additional_deps, repo_deps = dependencies.partition do |d|
          d.requirements.first[:groups].include?("additional_dependencies")
        end

        expect(repo_deps.length).to eq(4)
        expect(additional_deps.length).to eq(6)
      end

      it "parses a simple dart additional dependency" do
        dep = dependencies.find { |d| d.name == "intl" }
        expect(dep).not_to be_nil
        expect(dep.version).to eq("0.18.0")
        expect(dep.requirements.first[:requirement]).to eq("0.18.0")
        expect(dep.requirements.first[:source][:language]).to eq("dart")
        expect(dep.requirements.first[:source][:package_name]).to eq("intl")
        expect(dep.requirements.first[:source][:hook_id]).to eq("dart-format")
        expect(dep.requirements.first[:source][:original_string]).to eq("intl:0.18.0")
      end

      it "parses a caret-range dart additional dependency" do
        dep = dependencies.find { |d| d.name == "json_annotation" }
        expect(dep).not_to be_nil
        expect(dep.version).to eq("4.8.0")
        expect(dep.requirements.first[:requirement]).to eq("^4.8.0")
        expect(dep.requirements.first[:source][:language]).to eq("dart")
      end

      it "parses a >= constraint dart additional dependency" do
        dep = dependencies.find { |d| d.name == "collection" }
        expect(dep).not_to be_nil
        expect(dep.version).to eq("1.17.0")
        expect(dep.requirements.first[:requirement]).to eq(">=1.17.0")
      end

      it "parses a tilde-range dart additional dependency" do
        dep = dependencies.find { |d| d.name == "yaml" }
        expect(dep).not_to be_nil
        expect(dep.version).to eq("3.1.0")
        expect(dep.requirements.first[:requirement]).to eq("~3.1.0")
      end
    end

    context "when language is not specified locally but exists in hook source repo" do
      let(:pre_commit_config) do
        Dependabot::DependencyFile.new(
          name: ".pre-commit-config.yaml",
          content: fixture("pre_commit_configs", "without_language_field.yaml")
        )
      end
      let(:hook_language_fetcher) { instance_double(described_class::HookLanguageFetcher) }

      before do
        allow(described_class::HookLanguageFetcher).to receive(:new).and_return(hook_language_fetcher)

        # Mock the language fetcher for black hook
        allow(hook_language_fetcher).to receive(:fetch_language)
          .with(repo_url: "https://github.com/psf/black", revision: "24.1.1", hook_id: "black")
          .and_return("python")

        # Mock the language fetcher for eslint hook
        allow(hook_language_fetcher).to receive(:fetch_language)
          .with(repo_url: "https://github.com/pre-commit/mirrors-eslint", revision: "v8.56.0", hook_id: "eslint")
          .and_return("node")
      end

      it "fetches language from hook source repository" do
        repo_deps = dependencies.reject { |d| d.requirements.first[:groups].include?("additional_dependencies") }
        additional_deps = dependencies.select { |d| d.requirements.first[:groups].include?("additional_dependencies") }

        expect(repo_deps.length).to eq(2)
        expect(additional_deps.length).to eq(5)
      end

      it "parses python additional dependencies using fetched language" do
        dep = dependencies.find { |d| d.name == "black" }
        expect(dep).not_to be_nil
        expect(dep.requirements.first[:source][:language]).to eq("python")
        expect(dep.requirements.first[:source][:hook_id]).to eq("black")
        expect(dep.requirements.first[:source][:extras]).to eq("d")
      end

      it "parses node additional dependencies using fetched language" do
        dep = dependencies.find { |d| d.name == "eslint" }
        expect(dep).not_to be_nil
        expect(dep.requirements.first[:source][:language]).to eq("node")
        expect(dep.requirements.first[:source][:hook_id]).to eq("eslint")
      end
    end

    context "when language cannot be determined from local config or source repo" do
      let(:pre_commit_config) do
        Dependabot::DependencyFile.new(
          name: ".pre-commit-config.yaml",
          content: fixture("pre_commit_configs", "without_language_field.yaml")
        )
      end
      let(:hook_language_fetcher) { instance_double(described_class::HookLanguageFetcher) }

      before do
        allow(described_class::HookLanguageFetcher).to receive(:new).and_return(hook_language_fetcher)

        # Mock the language fetcher to return nil (language not found)
        allow(hook_language_fetcher).to receive(:fetch_language).and_return(nil)
      end

      it "skips additional dependencies when language is unknown" do
        repo_deps = dependencies.reject { |d| d.requirements.first[:groups].include?("additional_dependencies") }
        additional_deps = dependencies.select { |d| d.requirements.first[:groups].include?("additional_dependencies") }

        expect(repo_deps.length).to eq(2)
        expect(additional_deps.length).to eq(0)
      end
    end
  end
end
