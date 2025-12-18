# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency"
require "dependabot/dependency_file"
require "dependabot/uv/update_checker/pip_compile_version_resolver"

RSpec.describe Dependabot::Uv::UpdateChecker::PipCompileVersionResolver do
  let(:resolver) do
    described_class.new(
      dependency: dependency,
      dependency_files: dependency_files,
      credentials: credentials,
      repo_contents_path: nil
    )
  end
  let(:credentials) do
    [Dependabot::Credential.new(
      {
        "type" => "git_source",
        "host" => "github.com",
        "username" => "x-access-token",
        "password" => "token"
      }
    )]
  end
  let(:dependency_files) { [manifest_file, compiled_file] }
  let(:manifest_file) do
    Dependabot::DependencyFile.new(
      name: "requirements/test.in",
      content: fixture("pip_compile_files", manifest_fixture_name)
    )
  end
  let(:compiled_file) do
    Dependabot::DependencyFile.new(
      name: "requirements/test.txt",
      content: fixture("requirements", compiled_fixture_name)
    )
  end
  let(:manifest_fixture_name) { "unpinned.in" }
  let(:compiled_fixture_name) { "uv_pip_compile_unpinned.txt" }
  let(:dependency) do
    Dependabot::Dependency.new(
      name: dependency_name,
      version: dependency_version,
      requirements: dependency_requirements,
      package_manager: "uv"
    )
  end
  let(:dependency_name) { "attrs" }
  let(:dependency_version) { "17.3.0" }
  let(:dependency_requirements) do
    [{
      file: "requirements/test.in",
      requirement: nil,
      groups: [],
      source: nil
    }]
  end

  describe "#pip_compile_options_fingerprint" do
    subject(:fingerprint) { resolver.send(:pip_compile_options_fingerprint, options) }

    context "with standard options" do
      let(:options) { "--output-file=test.txt --index-url=https://pypi.org/simple" }

      it "redacts the output-file and index-url" do
        expect(fingerprint)
          .to eq("--output-file=<output_file> --index-url=<index_url>")
      end
    end

    context "with python-version option" do
      let(:options) { "--universal --python-version=3.8 --output-file=test.txt" }

      it "redacts the python-version value" do
        expect(fingerprint)
          .to eq("--universal --python-version=<python_version> --output-file=<output_file>")
      end
    end

    context "with extra-index-url option" do
      let(:options) { "--extra-index-url=https://private.pypi.org/simple --output-file=test.txt" }

      it "redacts the extra-index-url" do
        expect(fingerprint)
          .to eq("--extra-index-url=<extra_index_url> --output-file=<output_file>")
      end
    end
  end

  describe "#uv_pip_compile_options_from_compiled_file" do
    subject(:options) { resolver.send(:uv_pip_compile_options_from_compiled_file, compiled_file) }

    context "with a basic compiled file" do
      let(:compiled_fixture_name) { "uv_pip_compile_unpinned.txt" }

      it "extracts the standard options" do
        expect(options).to include("--no-emit-index-url")
        expect(options).not_to include("--universal")
        expect(options).not_to include("--python-version=")
      end
    end

    context "with universal and python-version flags" do
      let(:compiled_fixture_name) { "uv_pip_compile_universal.txt" }

      it "extracts the universal flag" do
        expect(options).to include("--universal")
      end

      it "extracts the python-version flag" do
        expect(options).to include("--python-version=3.8")
      end
    end

    context "with python-version including patch version" do
      let(:compiled_fixture_name) { "uv_pip_compile_universal_patch.txt" }

      it "extracts the full python-version including patch" do
        expect(options).to include("--python-version=3.11.2")
      end
    end

    context "with generate-hashes flag" do
      let(:compiled_fixture_name) { "uv_pip_compile_hashes.txt" }

      it "extracts the generate-hashes flag" do
        expect(options).to include("--generate-hashes")
      end
    end

    context "with no-annotate flag" do
      let(:compiled_fixture_name) { "uv_pip_compile_bounded.txt" }

      it "extracts the no-annotate flag" do
        expect(options).to include("--no-annotate")
      end
    end
  end
end
