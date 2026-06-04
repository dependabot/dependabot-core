# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/workflow_summary"
require "dependabot/environment"

RSpec.describe Dependabot::WorkflowSummary do
  subject(:summary) { described_class.new }

  describe "#record_result" do
    it "accumulates results" do
      summary.record_result(directory: "/src", status: "Success", details: "42 dependencies")
      summary.record_result(directory: "/lib", status: "Failed", details: "timeout")

      markdown = summary.build_markdown(command: "graph", package_manager: "bundler")

      expect(markdown).to include("| `/src` | ✅ Success | 42 dependencies |")
      expect(markdown).to include("| `/lib` | ❌ Failed | timeout |")
    end
  end

  describe "#build_markdown" do
    before do
      summary.record_result(directory: "/src", status: "Success", details: "42 dependencies")
      summary.record_result(directory: "/lib", status: "Degraded", details: "error fetching sub-dependencies")
      summary.record_result(directory: "/tools", status: "Failed", details: "dependency_file_not_resolvable")
      summary.record_result(directory: "/docs", status: "Skipped", details: "missing manifest files")
    end

    it "uses 'Dependency Graph Snapshot' heading for graph commands" do
      markdown = summary.build_markdown(command: "graph", package_manager: "go_modules")

      expect(markdown).to include("## Dependency Graph Snapshot — go_modules")
      expect(markdown).to include("| Directory | Status | Details |")
      expect(markdown).to include("| `/src` | ✅ Success | 42 dependencies |")
      expect(markdown).to include("| `/lib` | ⚠️ Degraded | error fetching sub-dependencies |")
      expect(markdown).to include("| `/tools` | ❌ Failed | dependency_file_not_resolvable |")
      expect(markdown).to include("| `/docs` | ⏭️ Skipped | missing manifest files |")
    end

    it "uses 'Dependency Update' heading for non-graph commands" do
      markdown = summary.build_markdown(command: "", package_manager: "npm_and_yarn")

      expect(markdown).to include("## Dependency Update — npm_and_yarn")
    end

    it "handles no recorded results" do
      empty_summary = described_class.new
      markdown = empty_summary.build_markdown(command: "graph", package_manager: "bundler")

      expect(markdown).to include("## Dependency Graph Snapshot — bundler")
      expect(markdown).to include("| Directory | Status | Details |")
    end

    it "replaces newlines in details with br tags to preserve readability" do
      markdown = described_class.new.tap do |s|
        s.record_result(directory: "/app", status: "Failed", details: "line one\nline two\n  line three")
      end.build_markdown(command: "graph", package_manager: "bundler")

      expect(markdown).to include("| `/app` | ❌ Failed | line one<br>line two<br>line three |")
    end

    it "groups multiple results for the same directory and status" do
      grouped_summary = described_class.new
      grouped_summary.record_result(directory: "/lib", status: "Warning", details: "missing credentials for registry X")
      grouped_summary.record_result(directory: "/lib", status: "Warning", details: "stale lockfile detected")
      grouped_summary.record_result(directory: "/lib", status: "Failed", details: "dependency_file_not_resolvable")
      grouped_summary.record_result(directory: "/src", status: "Success", details: "10 dependencies")

      markdown = grouped_summary.build_markdown(command: "graph", package_manager: "go_modules")

      # Sorted by [directory, status]: Failed comes before Warning alphabetically
      expect(markdown).to include("| `/lib` | ❌ Failed | dependency_file_not_resolvable |")
      expect(markdown).to include("|  | ⚠️ Warning | missing credentials for registry X |")
      expect(markdown).to include("|  |  | stale lockfile detected |")
      expect(markdown).to include("| `/src` | ✅ Success | 10 dependencies |")
    end
  end

  describe "#write" do
    let(:output_path) { File.join(Dir.tmpdir, "dependabot-test-#{SecureRandom.hex(4)}", "output.json") }

    before do
      FileUtils.mkdir_p(File.dirname(output_path))
      allow(Dependabot::Environment).to receive(:github_actions?).and_return(github_actions)
      allow(Dependabot::Environment).to receive(:output_path).and_return(output_path)
    end

    after do
      FileUtils.rm_rf(File.dirname(output_path))
    end

    context "when running in GitHub Actions" do
      let(:github_actions) { true }

      it "writes the summary markdown file with the correct heading" do
        summary.record_result(directory: "/", status: "Success", details: "10 dependencies")

        summary.write(command: "graph", package_manager: "go_modules")

        summary_path = File.join(File.dirname(output_path), "summary.md")
        expect(File.exist?(summary_path)).to be true

        content = File.read(summary_path)
        expect(content).to include("## Dependency Graph Snapshot — go_modules")
        expect(content).to include("| `/` | ✅ Success | 10 dependencies |")
      end

      it "writes an empty file when there are no results" do
        summary.write(command: "graph", package_manager: "bundler")

        summary_path = File.join(File.dirname(output_path), "summary.md")
        expect(File.exist?(summary_path)).to be true
        expect(File.read(summary_path)).to eq("")
      end
    end

    context "when not running in GitHub Actions" do
      let(:github_actions) { false }

      it "does not write a file" do
        summary.record_result(directory: "/", status: "Success", details: "10 dependencies")

        summary.write(command: "graph", package_manager: "bundler")

        summary_path = File.join(File.dirname(output_path), "summary.md")
        expect(File.exist?(summary_path)).to be false
      end
    end
  end
end
