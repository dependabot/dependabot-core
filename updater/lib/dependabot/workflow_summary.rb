# typed: strict
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
      return unless path

      if @results.empty?
        # Ensure we write an empty file even if no summary is required
        File.write(path, "")
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

      last_directory = T.let("", String)
      @results.sort_by { |r| [r.directory, r.status] }
              .group_by { |r| [r.directory, r.status] }
              .each_value do |results|
        results.each_with_index do |result, index|
          sanitized_details = result.details.strip.gsub(/\s*\n\s*/, "<br>")
          status_icon = status_emoji(result.status)

          dir_cell = result.directory == last_directory ? "" : "`#{result.directory}`"
          status_cell = index.zero? ? "#{status_icon} #{result.status.capitalize}" : ""

          lines << "| #{dir_cell} | #{status_cell} | #{sanitized_details} |"
          last_directory = result.directory
        end
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

    sig { returns(T.nilable(String)) }
    def summary_path
      output_path = Dependabot::Environment.output_path
      File.join(File.dirname(output_path), SUMMARY_FILENAME)
    rescue StandardError
      nil
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
