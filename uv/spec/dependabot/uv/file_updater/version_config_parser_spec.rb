# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/uv/file_updater/version_config_parser"

RSpec.describe Dependabot::Uv::FileUpdater::VersionConfigParser do
  describe "#parse" do
    subject(:config) { parser.parse }

    let(:parser) do
      described_class.new(
        pyproject_content: pyproject_content,
        base_path: base_path,
        repo_root: repo_root
      )
    end
    let(:base_path) { "." }
    let(:repo_root) { "." }

    context "with setuptools-scm version_file configuration" do
      let(:pyproject_content) { fixture("pyproject_files", "setuptools_scm_version_file.toml") }

      it "extracts the write path" do
        expect(config.write_paths).to eq(["src/display/_version.py"])
      end

      it "extracts the fallback version" do
        expect(config.fallback_version).to eq("0.0.0")
      end

      it "extracts the package name" do
        expect(config.package_name).to eq("toggle-display-input")
      end

      it "has dynamic version" do
        expect(config.dynamic_version?).to be true
      end

      it "has no source paths" do
        expect(config.source_paths).to be_empty
      end
    end

    context "with hatch-vcs build hook configuration" do
      let(:pyproject_content) { fixture("pyproject_files", "hatch_vcs_build_hook.toml") }

      it "extracts the write path from build hook" do
        expect(config.write_paths).to eq(["p1/_version.py"])
      end

      it "extracts the fallback version from raw-options" do
        expect(config.fallback_version).to eq("10.0.0")
      end

      it "extracts the package name" do
        expect(config.package_name).to eq("p1")
      end

      it "has dynamic version" do
        expect(config.dynamic_version?).to be true
      end
    end

    context "with hatch version external path configuration" do
      let(:pyproject_content) { fixture("pyproject_files", "hatch_version_external_path.toml") }
      # This simulates libs/demo/pyproject.toml referencing ../../.release-manifest.json
      let(:base_path) { "libs/demo" }

      it "extracts and resolves the source path relative to repo root" do
        expect(config.source_paths).to eq([".release-manifest.json"])
      end

      it "has no write paths" do
        expect(config.write_paths).to be_empty
      end

      it "extracts the package name" do
        expect(config.package_name).to eq("demo")
      end

      it "has dynamic version" do
        expect(config.dynamic_version?).to be true
      end
    end

    context "with workspace member base path" do
      let(:pyproject_content) { fixture("pyproject_files", "hatch_vcs_build_hook.toml") }
      let(:base_path) { "packages/p1" }

      it "resolves write paths relative to base path" do
        expect(config.write_paths).to eq(["packages/p1/p1/_version.py"])
      end
    end

    context "with path outside repo root" do
      let(:pyproject_content) do
        <<~TOML
          [project]
          name = "escape-test"

          [tool.hatch.version]
          path = "../../../outside/version.txt"
        TOML
      end
      let(:base_path) { "subdir" }
      let(:repo_root) { "/repo" }

      it "filters out paths outside repo root" do
        expect(config.source_paths).to be_empty
      end
    end

    context "with absolute path" do
      let(:pyproject_content) do
        <<~TOML
          [project]
          name = "absolute-test"

          [tool.setuptools_scm]
          version_file = "/absolute/path/_version.py"
        TOML
      end

      it "filters out absolute paths" do
        expect(config.write_paths).to be_empty
      end
    end

    context "with no dynamic version configuration" do
      let(:pyproject_content) { fixture("pyproject_files", "uv_simple.toml") }

      it "has no write paths" do
        expect(config.write_paths).to be_empty
      end

      it "has no source paths" do
        expect(config.source_paths).to be_empty
      end

      it "has no fallback version" do
        expect(config.fallback_version).to be_nil
      end

      it "does not have dynamic version" do
        expect(config.dynamic_version?).to be false
      end
    end

    context "with invalid TOML" do
      let(:pyproject_content) { "invalid toml content {{{" }

      it "returns empty config" do
        expect(config.write_paths).to be_empty
        expect(config.source_paths).to be_empty
        expect(config.fallback_version).to be_nil
        expect(config.package_name).to be_nil
      end
    end

    context "with setuptools-scm legacy write_to configuration" do
      let(:pyproject_content) do
        <<~TOML
          [project]
          name = "legacy-scm"

          [tool.setuptools_scm]
          write_to = "src/package/_version.py"
          fallback_version = "1.0.0"
        TOML
      end

      it "extracts the write path from write_to" do
        expect(config.write_paths).to eq(["src/package/_version.py"])
      end

      it "extracts the fallback version" do
        expect(config.fallback_version).to eq("1.0.0")
      end
    end

    context "with both version_file and write_to" do
      let(:pyproject_content) do
        <<~TOML
          [project]
          name = "both-configs"

          [tool.setuptools_scm]
          version_file = "src/new/_version.py"
          write_to = "src/old/_version.py"
        TOML
      end

      it "extracts both write paths" do
        expect(config.write_paths).to contain_exactly("src/new/_version.py", "src/old/_version.py")
      end
    end
  end
end
