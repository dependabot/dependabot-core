# typed: strict
# frozen_string_literal: true

require "sorbet-runtime"

require "dependabot/environment"

module Dependabot
  # Builds and writes a GitHub Actions Job Summary markdown file for graph jobs.
  # The summary is written to the output directory where it can be extracted
  # by the dependabot-action and appended to $GITHUB_STEP_SUMMARY.
  module JobSummary
    extend T::Sig

    SUMMARY_FILENAME = "summary.md"

    class DirectoryResult < T::Struct
      const :directory, String
      const :status, String
      const :details, String
    end

    sig { params(results: T::Array[DirectoryResult]).void }
    def self.write(results)
      return unless Dependabot::Environment.github_actions?

      path = summary_path
      return unless path

      markdown = build_markdown(results)
      File.write(path, markdown)
      Dependabot.logger.info("Job summary written to #{path}")
    end

    sig { params(results: T::Array[DirectoryResult]).returns(String) }
    def self.build_markdown(results)
      lines = []
      lines << "## Dependency Graph Snapshot"
      lines << ""
      lines << "| Directory | Status | Details |"
      lines << "|-----------|--------|---------|"

      results.each do |result|
        status_icon = status_emoji(result.status)
        lines << "| `#{result.directory}` | #{status_icon} #{result.status} | #{result.details} |"
      end

      lines << ""
      lines.join("\n")
    end

    sig { returns(T.nilable(String)) }
    def self.summary_path
      output_path = Dependabot::Environment.output_path
      File.join(File.dirname(output_path), SUMMARY_FILENAME)
    rescue StandardError
      nil
    end

    sig { params(status: String).returns(String) }
    private_class_method def self.status_emoji(status)
      case status.downcase
      when "success" then "✅"
      when "degraded" then "⚠️"
      when "failed" then "❌"
      when "skipped" then "⏭️"
      else "❓"
      end
    end
  end
end
