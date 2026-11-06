# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency"
require "dependabot/error_report_context"
require "dependabot/shared_helpers"

RSpec.describe Dependabot::ErrorReportContext do
  describe ".build" do
    subject(:context) { described_class.build(error: error) }

    context "with an error that has no context" do
      let(:error) { RuntimeError.new("No files have changed!") }

      it { is_expected.to be_nil }
    end

    context "with a helper subprocess failure" do
      let(:error) do
        Dependabot::SharedHelpers::HelperSubprocessFailed.new(
          message: "boom",
          error_class: "VersionResolutionError",
          error_context: {
            command: "pyenv exec pip-compile --index-url https://user:secret@example.com",
            function: "resolve_dependencies",
            args: { "token" => "secret" },
            stderr_output: "secret output",
            time_taken: 1.5,
            process_exit_value: "pid 4242 exit 1",
            process_termsig: nil
          }
        )
      end

      it "only forwards allowlisted values" do
        expect(context).to eq(
          "helper-function" => "resolve_dependencies",
          "helper-exit-status" => "exit 1",
          "helper-time-taken" => 1.5,
          "helper-error-class" => "VersionResolutionError"
        )
      end
    end

    context "with a no-change error carrying sentry context" do
      let(:error_class) do
        Class.new(StandardError) do
          include Dependabot::HasSentryContext

          def sentry_context
            {
              extra: {
                dependencies: [{ "name" => "lodash", "version" => "4.17.21" }, { "name" => "react" }],
                updated_files: [],
                dependency_files: ["package.json", "pnpm-lock.yaml"],
                package_manager: "pnpm",
                lockfile_content: "secret"
              }
            }
          end
        end
      end
      let(:error) { error_class.new("No files were updated!") }

      it "forwards dependency and file names" do
        expect(context).to eq(
          "dependency-names" => %w(lodash react),
          "dependency-files" => ["package.json", "pnpm-lock.yaml"],
          "package-manager-name" => "pnpm"
        )
      end
    end

    context "with an Excon HTTP status error" do
      let(:error) do
        Excon::Error::NotFound.new(
          "Expected(200) <=> Actual(404 Not Found)",
          { method: :get, scheme: "https", host: "registry.npmjs.org", path: "/lodash", query: "token=secret" },
          Excon::Response.new(status: 404)
        )
      end

      it "forwards the method, host and status" do
        expect(context).to eq(
          "http-method" => "GET",
          "host" => "registry.npmjs.org",
          "http-status" => 404
        )
      end
    end

    context "with an Excon HTTP status error built from a raw response hash" do
      let(:error) do
        Excon::Error::NotFound.new("Not Found", { method: :get, host: "registry.npmjs.org" }, { status: 404 })
      end

      it "forwards the status" do
        expect(context).to include("http-status" => 404)
      end
    end

    context "with an Excon HTTP status error raised by a request" do
      let(:error) do
        stub_request(:get, "https://registry.npmjs.org/lodash").to_return(status: 503)
        Excon.get("https://registry.npmjs.org/lodash", expects: [200])
      rescue Excon::Error::HTTPStatus => e
        e
      end

      it "forwards the method, host and status" do
        expect(context).to eq(
          "http-method" => "GET",
          "host" => "registry.npmjs.org",
          "http-status" => 503
        )
      end
    end

    context "with a wrapped error" do
      let(:error) do
        begin
          begin
            raise Excon::Error::Socket, EOFError.new
          rescue Excon::Error::Socket => e
            described_class.attach(e, { http_method: "GET", host: "pypi.org" })
            raise
          end
        rescue Excon::Error::Socket
          raise Dependabot::DependabotError, "Registry unreachable"
        end
      rescue Dependabot::DependabotError => e
        described_class.attach(e, { host: "files.pythonhosted.org" })
        e
      end

      it "merges context from causes, preferring the reported error" do
        expect(context).to eq(
          "socket-error-class" => "EOFError",
          "http-method" => "GET",
          "host" => "files.pythonhosted.org",
          "cause-class" => "Excon::Error::Socket"
        )
      end
    end

    context "with a dependency" do
      subject(:context) { described_class.build(error: RuntimeError.new("boom"), dependency: dependency) }

      let(:dependency) do
        Dependabot::Dependency.new(
          name: "requests",
          version: "2.32.0",
          previous_version: "2.31.0",
          package_manager: "pip",
          requirements: [{ file: "requirements.txt", requirement: "==2.32.0", groups: [], source: nil }]
        )
      end

      it "truncates long dependency values" do
        long_dependency = Dependabot::Dependency.new(
          name: "a" * 600, version: "1.0.0", package_manager: "pip", requirements: []
        )
        long_context = described_class.build(error: RuntimeError.new("boom"), dependency: long_dependency)

        expect(long_context["dependency-name"]).to eq("#{'a' * 500}...")
        expect(long_context).not_to have_key("dependency-requirement-files")
      end

      it "describes the dependency being updated" do
        expect(context).to eq(
          "dependency-name" => "requests",
          "dependency-version" => "2.32.0",
          "dependency-previous-version" => "2.31.0",
          "dependency-requirement-files" => ["requirements.txt"]
        )
      end
    end
  end

  describe ".attach" do
    it "drops values that cannot be safely serialized" do
      error = RuntimeError.new("boom")
      described_class.attach(error, { file_name: "go.mod", object: Object.new, attempts: 2, ratio: Float::NAN })

      expect(described_class.build(error: error)).to eq("file-name" => "go.mod", "attempts" => 2)
    end
  end

  describe ".host_for" do
    it "returns only the host" do
      expect(described_class.host_for("https://user:pass@npm.fury.io/secret-token/pkg?token=abc"))
        .to eq("npm.fury.io")
    end

    it "redacts unparseable URLs" do
      expect(described_class.host_for("not a url")).to eq("<redacted>")
    end
  end
end
