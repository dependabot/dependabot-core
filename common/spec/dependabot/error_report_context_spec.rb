# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency"
require "dependabot/error_report_context"
require "dependabot/errors"

RSpec.describe Dependabot::ErrorReportContext do
  describe ".build" do
    subject(:context) { described_class.build(error: error) }

    context "with an error that has no context" do
      let(:error) { RuntimeError.new("No files have changed!") }

      it { is_expected.to be_nil }
    end

    context "with a wrapped error" do
      let(:error) do
        begin
          begin
            raise IOError, "connection closed"
          rescue IOError => e
            described_class.attach(e, { http_method: "GET", host: "pypi.org" })
            raise
          end
        rescue IOError
          raise Dependabot::DependabotError, "Registry unreachable"
        end
      rescue Dependabot::DependabotError => e
        described_class.attach(e, { host: "files.pythonhosted.org" })
        e
      end

      it "merges context from causes, preferring the reported error" do
        expect(context).to eq(
          "http-method" => "GET",
          "host" => "files.pythonhosted.org"
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
