# frozen_string_literal: true

require "dependabot/metadata_finders/base"

module Dependabot
  module MetadataFinders
    class Base
      class ChangelogPruner
        attr_reader :dependency, :changelog_text

        def initialize(dependency:, changelog_text:)
          @dependency = dependency
          @changelog_text = changelog_text
        end

        def includes_new_version?
          !new_version_changelog_line.nil?
        end

        # rubocop:disable Metrics/PerceivedComplexity
        # rubocop:disable Metrics/CyclomaticComplexity
        def pruned_text
          changelog_lines = changelog_text.split("\n")

          slice_range =
            if old_version_changelog_line && new_version_changelog_line
              if old_version_changelog_line < new_version_changelog_line
                Range.new(old_version_changelog_line, -1)
              else
                Range.new(new_version_changelog_line,
                          old_version_changelog_line - 1)
              end
            elsif old_version_changelog_line
              return if old_version_changelog_line.zero?

              # Assumes changelog is in descending order
              Range.new(0, old_version_changelog_line - 1)
            elsif new_version_changelog_line
              # Assumes changelog is in descending order
              Range.new(new_version_changelog_line, -1)
            else
              return unless changelog_contains_relevant_versions?

              # If the changelog contains any relevant versions, return it in
              # full. We could do better here by fully parsing the changelog
              Range.new(0, -1)
            end

          changelog_lines.slice(slice_range).join("\n").sub(/\n*\z/, "")
        end
        # rubocop:enable Metrics/PerceivedComplexity
        # rubocop:enable Metrics/CyclomaticComplexity

        private

        def old_version_changelog_line
          old_version = git_source? ? previous_ref : dependency.previous_version
          return nil unless old_version

          changelog_line_for_version(old_version)
        end

        def new_version_changelog_line
          return nil unless new_version

          changelog_line_for_version(new_version)
        end

        # rubocop:disable Metrics/CyclomaticComplexity
        # rubocop:disable Metrics/PerceivedComplexity
        def changelog_line_for_version(version)
          raise "No changelog text" unless changelog_text
          return nil unless version

          version = version.gsub(/^v/, "")
          escaped_version = Regexp.escape(version)

          changelog_lines = changelog_text.split("\n")

          changelog_lines.find_index.with_index do |line, index|
            next false unless line.match?(/(?<!\.)#{escaped_version}(?![.\-])/)
            next false if line.match?(/#{escaped_version}\.\./)
            next true if line.start_with?("#", "!", "==")
            next true if line.match?(/^v?#{escaped_version}:?/)
            next true if line.match?(/^[\+\*\-] (version )?#{escaped_version}/i)
            next true if line.match?(/^\d{4}-\d{2}-\d{2}/)
            next true if changelog_lines[index + 1]&.match?(/^[=\-\+]{3,}\s*$/)

            false
          end
        end
        # rubocop:enable Metrics/CyclomaticComplexity
        # rubocop:enable Metrics/PerceivedComplexity

        def changelog_contains_relevant_versions?
          # Assume the changelog is relevant if we can't parse the new version
          return true unless version_class.correct?(dependency.version)

          # Assume the changelog is relevant if it mentions the new version
          # anywhere
          return true if changelog_text.include?(dependency.version)

          # Otherwise check if any intermediate versions are included in headers
          versions_in_changelog_headers.any? do |version|
            next false unless version <= version_class.new(dependency.version)
            next true unless dependency.previous_version
            next true unless version_class.correct?(dependency.previous_version)

            version > version_class.new(dependency.previous_version)
          end
        end

        def versions_in_changelog_headers
          changelog_lines = changelog_text.split("\n")
          header_lines =
            changelog_lines.select.with_index do |line, index|
              next true if line.start_with?("#", "!")
              next true if line.match?(/^v?\d\.\d/)
              next true if changelog_lines[index + 1]&.match?(/^[=-]+\s*$/)

              false
            end

          versions = []
          header_lines.each do |line|
            cleaned_line = line.gsub(/^[^0-9]*/, "").gsub(/[\s,:].*/, "")
            next if cleaned_line.empty? || !version_class.correct?(cleaned_line)

            versions << version_class.new(cleaned_line)
          end

          versions
        end

        def new_version
          @new_version ||= git_source? ? new_ref : dependency.version
          @new_version&.gsub(/^v/, "")
        end

        def previous_ref
          dependency.previous_requirements.map do |r|
            r.dig(:source, "ref") || r.dig(:source, :ref)
          end.compact.first
        end

        def new_ref
          dependency.requirements.map do |r|
            r.dig(:source, "ref") || r.dig(:source, :ref)
          end.compact.first
        end

        def ref_changed?
          previous_ref && new_ref && previous_ref != new_ref
        end

        # TODO: Refactor me so that Composer doesn't need to be special cased
        def git_source?
          # Special case Composer, which uses git as a source but handles tags
          # internally
          return false if dependency.package_manager == "composer"

          requirements = dependency.requirements
          sources = requirements.map { |r| r.fetch(:source) }.uniq.compact
          return false if sources.empty?
          raise "Multiple sources! #{sources.join(', ')}" if sources.count > 1

          source_type = sources.first[:type] || sources.first.fetch("type")
          source_type == "git"
        end

        def version_class
          Utils.version_class_for_package_manager(dependency.package_manager)
        end
      end
    end
  end
end
