# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/job_summary"
require "dependabot/environment"

RSpec.describe Dependabot::JobSummary do
  describe ".build_markdown" do
    it "renders a markdown table with all status types" do
      results = [
        Dependabot::JobSummary::DirectoryResult.new(
          directory: "/src",
          status: "Success",
          details: "42 dependencies"
        ),
        Dependabot::JobSummary::DirectoryResult.new(
          directory: "/lib",
          status: "Degraded",
          details: "error fetching sub-dependencies"
        ),
        Dependabot::JobSummary::DirectoryResult.new(
          directory: "/tools",
          status: "Failed",
          details: "dependency_file_not_resolvable"
        ),
        Dependabot::JobSummary::DirectoryResult.new(
          directory: "/docs",
          status: "Skipped",
          details: "missing manifest files"
        )
      ]

      markdown = described_class.build_markdown(results)

      expect(markdown).to include("## Dependency Graph Snapshot")
      expect(markdown).to include("| Directory | Status | Details |")
      expect(markdown).to include("| `/src` | ✅ Success | 42 dependencies |")
      expect(markdown).to include("| `/lib` | ⚠️ Degraded | error fetching sub-dependencies |")
      expect(markdown).to include("| `/tools` | ❌ Failed | dependency_file_not_resolvable |")
      expect(markdown).to include("| `/docs` | ⏭️ Skipped | missing manifest files |")
    end

    it "handles an empty results array" do
      markdown = described_class.build_markdown([])

      expect(markdown).to include("## Dependency Graph Snapshot")
      expect(markdown).to include("| Directory | Status | Details |")
    end
  end

  describe ".write" do
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

      it "writes the summary markdown file" do
        results = [
          Dependabot::JobSummary::DirectoryResult.new(
            directory: "/",
            status: "Success",
            details: "10 dependencies"
          )
        ]

        described_class.write(results)

        summary_path = File.join(File.dirname(output_path), "summary.md")
        expect(File.exist?(summary_path)).to be true

        content = File.read(summary_path)
        expect(content).to include("## Dependency Graph Snapshot")
        expect(content).to include("| `/` | ✅ Success | 10 dependencies |")
      end
    end

    context "when not running in GitHub Actions" do
      let(:github_actions) { false }

      it "does not write a file" do
        results = [
          Dependabot::JobSummary::DirectoryResult.new(
            directory: "/",
            status: "Success",
            details: "10 dependencies"
          )
        ]

        described_class.write(results)

        summary_path = File.join(File.dirname(output_path), "summary.md")
        expect(File.exist?(summary_path)).to be false
      end
    end
  end
end
