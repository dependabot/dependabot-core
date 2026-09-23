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

    context "with both fallback version sources" do
      let(:fallback_version) { "1.2.3" }
      let(:pyproject_content) do
        <<~TOML
          [tool.setuptools_scm]
          fallback_version = #{fallback_version.to_json}

          [tool.hatch.version.raw-options]
          fallback_version = "9.0.0"
        TOML
      end

      it "prefers the setuptools-scm fallback" do
        expect(config.fallback_version).to eq("1.2.3")
      end

      context "when the setuptools-scm fallback is empty" do
        let(:fallback_version) { "" }

        it "keeps the empty fallback" do
          expect(config.fallback_version).to eq("")
        end
      end

      context "when the setuptools-scm fallback is not a string" do
        let(:fallback_version) { 123 }

        it "uses the Hatch fallback" do
          expect(config.fallback_version).to eq("9.0.0")
        end
      end
    end

    context "with non-string optional values" do
      let(:pyproject_content) do
        <<~TOML
          [project]
          name = 123

          [tool.setuptools_scm]
          version_file = 123
          write_to = false
          fallback_version = ["1.0.0"]

          [tool.hatch.build.hooks.vcs]
          version-file = ["_version.py"]

          [tool.hatch.version]
          path = 123

          [tool.hatch.version.raw-options]
          fallback_version = 456
        TOML
      end

      it "ignores the invalid optional values" do
        expect(config).to have_attributes(
          write_paths: [],
          source_paths: [],
          fallback_version: nil,
          package_name: nil
        )
      end
    end

    context "with a non-table setuptools-scm configuration" do
      let(:pyproject_content) do
        <<~TOML
          [tool]
          setuptools_scm = false

          [tool.hatch.version.raw-options]
          fallback_version = "9.0.0"
        TOML
      end

      it "ignores that section without dropping other configuration" do
        expect(config.write_paths).to be_empty
        expect(config.fallback_version).to eq("9.0.0")
      end
    end

    context "with duplicate paths across build backends" do
      let(:pyproject_content) do
        <<~TOML
          [tool.setuptools_scm]
          version_file = "src/_version.py"
          write_to = "src/_version.py"

          [tool.hatch.build.hooks.vcs]
          version-file = "src/hatch_version.py"

          [tool.hatch.version]
          path = ".release-manifest.json"
        TOML
      end

      it "keeps the first occurrence of each output path in order" do
        expect(config.write_paths).to eq(["src/_version.py", "src/hatch_version.py"])
        expect(config.source_paths).to eq([".release-manifest.json"])
      end
    end

    context "with an empty document" do
      let(:pyproject_content) { "" }

      it "returns an empty configuration" do
        expect(config).to have_attributes(
          write_paths: [],
          source_paths: [],
          fallback_version: nil,
          package_name: nil
        )
      end
    end

    context "with unrelated configuration" do
      let(:pyproject_content) do
        <<~TOML
          [project]
          name = "example"

          [tool.unrelated]
          options = [1, false, { key = "value" }]
        TOML
      end

      it "ignores unknown sections" do
        expect(config.package_name).to eq("example")
        expect(config).not_to be_dynamic_version
      end

      it "parses the TOML only once" do
        allow(TomlRB).to receive(:parse).and_call_original

        parser.parse
        parser.parse

        expect(TomlRB).to have_received(:parse).with(pyproject_content).once
      end
    end

    context "with duplicate TOML keys" do
      let(:pyproject_content) do
        <<~TOML
          [project]
          name = "one"
          name = "two"
        TOML
      end

      it "returns an empty configuration" do
        expect(config).to have_attributes(
          write_paths: [],
          source_paths: [],
          fallback_version: nil,
          package_name: nil
        )
      end
    end

    context "with a non-table intermediate section" do
      let(:pyproject_content) { 'tool = "invalid"' }

      it "raises instead of treating the document as empty" do
        expect { config }.to raise_error(TypeError)
      end
    end
  end
end
