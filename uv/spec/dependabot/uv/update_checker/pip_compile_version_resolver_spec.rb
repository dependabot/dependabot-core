# typed: false
# Sorbet cannot resolve the child-context options fixture. https://srb.help/7003
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

  describe "#latest_resolvable_version" do
    subject(:latest_resolvable_version) { resolver.latest_resolvable_version }

    context "when the project's required-version needs a uv other than the bundled one" do
      let(:manifest_file) do
        # apache-airflow + unidecode makes python_env set AIRFLOW_GPL_UNIDECODE, which must survive the merge.
        Dependabot::DependencyFile.new(name: "requirements/test.in", content: "attrs\napache-airflow\nunidecode\n")
      end
      let(:uv_runs) { [] }

      before do
        allow(Dependabot::Uv::LanguageVersionManager).to receive(:new).and_return(
          instance_double(
            Dependabot::Uv::LanguageVersionManager,
            install_required_python: nil,
            python_major_minor: "3.11"
          )
        )
        allow(Dependabot::Uv::UvExecutable).to receive(:resolve).with(credentials: credentials).and_return(
          Dependabot::Uv::UvExecutable.new(
            command: "/opt/uv/bin/uv", fingerprint: "<uv_executable>", env: { "PATH" => "/pyenv/bin:/usr/bin" }
          )
        )
        allow(Dependabot::SharedHelpers).to receive(:with_git_configured).and_yield
        allow(Dependabot::SharedHelpers).to receive(:run_shell_command) do |command, fingerprint:, env:, **|
          next "" if command.start_with?("pyenv local ")
          raise "Unexpected command: #{command}" unless command.start_with?("/opt/uv/bin/uv pip compile ")

          uv_runs << { fingerprint: fingerprint, env: env }
          ""
        end
        allow(Dependabot::Uv::FileParser).to receive(:new).and_return(
          instance_double(
            Dependabot::Uv::FileParser,
            parse: [Dependabot::Dependency.new(
              name: "attrs",
              version: "18.1.0",
              requirements: [],
              package_manager: "uv"
            )]
          )
        )
      end

      it "compiles with that uv, its PATH and the existing Python env" do
        expect(latest_resolvable_version).to eq(Dependabot::Uv::Version.new("18.1.0"))
        expect(uv_runs.size).to eq(1)
        expect(uv_runs.first[:fingerprint]).to start_with("<uv_executable> pip compile -v ")
        expect(uv_runs.first[:env]).to eq("PATH" => "/pyenv/bin:/usr/bin", "AIRFLOW_GPL_UNIDECODE" => "yes")
      end

      context "with a transitive dependency, which is compiled a second time" do
        let(:dependency_requirements) { [] }

        it "uses that uv for both compiles" do
          expect(latest_resolvable_version).to eq(Dependabot::Uv::Version.new("18.1.0"))
          expect(uv_runs.map { |run| run[:fingerprint][/\A<uv_executable> pip compile (-v )?/] })
            .to eq(["<uv_executable> pip compile -v ", "<uv_executable> pip compile "])
          expect(uv_runs.map { |run| run[:env]["PATH"] }).to all(eq("/pyenv/bin:/usr/bin"))
        end
      end
    end
  end
end
