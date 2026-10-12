# typed: strong
# frozen_string_literal: true

require "sorbet-runtime"

require "dependabot/environment"

module Dependabot
  # Builds and writes a GitHub Actions Job Summary markdown file.
  # The summary is written to the output directory where it can be extracted
  # by the dependabot-action and appended to $GITHUB_STEP_SUMMARY.
  class WorkflowSummary
    extend T::Sig

    SUMMARY_FILENAME = "summary.md"

    class DirectoryResult < T::Struct
      const :directory, String
      const :status, String
      const :details, String
    end

    sig { void }
    def initialize
      @results = T.let([], T::Array[DirectoryResult])
    end

    sig { params(directory: String, status: String, details: String).void }
    def record_result(directory:, status:, details:)
      @results << DirectoryResult.new(
        directory: directory,
        status: status,
        details: details
      )
    end

    sig { params(command: String, package_manager: String).void }
    def write(command:, package_manager:)
      return unless Dependabot::Environment.github_actions?

      path = summary_path

      if @results.empty?
        # Ensure we write an empty file even if no summary is required
        File.write(path, "")
        Dependabot.logger.debug("Workflow summary blank, empty file written to #{path}")
        return
      end

      markdown = build_markdown(command: command, package_manager: package_manager)
      File.write(path, markdown)
      Dependabot.logger.info("Workflow summary written to #{path}")
    end

    sig { params(command: String, package_manager: String).returns(String) }
    def build_markdown(command:, package_manager:)
      lines = []
      lines << "## #{heading(command: command, package_manager: package_manager)}"
      lines << ""
      lines << "| Directory | Status | Details |"
      lines << "|-----------|--------|---------|"

      @results.group_by { |r| [r.directory, r.status] }
              .sort_by { |key, _| key }
              .each do |_, results|
        first = T.must(results.first)
        status_icon = status_emoji(first.status)
        combined_details = results.map { |r| r.details.strip.gsub(/\s*\n\s*/, "<br>") }
                                  .join("<br><br>")

        lines << "| `#{first.directory}` | #{status_icon} #{first.status.capitalize} | #{combined_details} |"
      end

      lines << ""
      lines.join("\n")
    end

    private

    sig { params(command: String, package_manager: String).returns(String) }
    def heading(command:, package_manager:)
      job_type = command == "graph" ? "Dependency Graph Snapshot" : "Dependency Update"
      "#{job_type} — #{package_manager}"
    end

    sig { returns(String) }
    def summary_path
      output_path = Dependabot::Environment.output_path
      File.join(File.dirname(output_path), SUMMARY_FILENAME)
    end

    sig { params(status: String).returns(String) }
    def status_emoji(status)
      case status.downcase
      when "ok" then "✅"
      when "degraded", "warning" then "⚠️"
      when "failed" then "❌"
      when "skipped" then "⏭️"
      else "❓"
      end
    end
  end
end
