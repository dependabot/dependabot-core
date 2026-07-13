# typed: strict
# frozen_string_literal: true

require "sorbet-runtime"
require "dependabot/shared_helpers"
require "dependabot/dependency"
require "dependabot/shared/shared_file_updater"
require "fileutils"
require "tmpdir"

module Dependabot
  module Helm
    class FileUpdater < Dependabot::Shared::SharedFileUpdater
      class ChartUpdater
        extend T::Sig

        sig do
          params(
            dependency: Dependabot::Dependency
          ).void
        end
        def initialize(dependency:)
          @dependency = dependency
        end

        # Returns the file content with this dependency's entries rewritten. May
        # return the content unchanged (e.g. a strategy that leaves an in-range
        # constraint alone, or a dependency not present in this file); the file
        # updater decides whether a file actually changed.
        sig { params(file: Dependabot::DependencyFile).returns(T.nilable(String)) }
        def updated_chart_yaml_content(file)
          content = file.content
          yaml_obj = YAML.safe_load(T.must(content))

          update_chart_dependencies(T.must(content), yaml_obj, file)
        end

        private

        sig { returns(Dependabot::Dependency) }
        attr_reader :dependency

        sig do
          params(
            content: String,
            yaml_obj: T::Hash[String, Object],
            file: Dependabot::DependencyFile
          ).returns(String)
        end
        def update_chart_dependencies(content, yaml_obj, file)
          return content unless update_chart_dependency?(file) && yaml_obj["dependencies"]

          # Rewrite each entry once, scanning forward so repeated occurrences of
          # the same chart update independently. A whole-file gsub per entry can
          # alias — after entry A is rewritten to entry B's old version, B's pass
          # would re-match the just-updated A.
          cursor = 0
          T.cast(yaml_obj["dependencies"], T::Array[T::Hash[String, Object]]).each do |dep|
            next unless dep["name"] == dependency.name

            old_version = dep["version"].to_s
            new_requirement = updated_requirement_string(file, old_version) || dependency.version.to_s
            # This occurrence's constraint is unchanged (the strategy left it
            # alone) — nothing to write for it.
            next if new_requirement == old_version

            new_content, cursor = replace_next_entry_version(
              content,
              cursor,
              old_version,
              yaml_safe_value(new_requirement)
            )
            # A changed constraint that produced no textual edit means the entry
            # wasn't matched (e.g. an unusual name/version layout). Surface it
            # rather than silently emitting a partial update.
            if new_content == content
              raise "Expected to update #{dependency.name} from #{old_version} to " \
                    "#{new_requirement} in #{file.name}, but no matching entry was found"
            end

            content = new_content
          end
          content
        end

        # Replaces this chart's next `version:` occurrence (at/after cursor) with
        # new_version, returning the updated content and the position just past
        # the rewrite so later entries match their own line. The name may be
        # quoted; returns the content unchanged when no entry matches.
        sig do
          params(content: String, cursor: Integer, old_version: String, new_version: String)
            .returns([String, Integer])
        end
        def replace_next_entry_version(content, cursor, old_version, new_version)
          pattern = /
            (\s+-\s+name:\s+["']?#{Regexp.escape(dependency.name)}["']?.*?\n\s+version:\s+)
            ["']?#{Regexp.escape(old_version)}["']?
          /mx
          match = pattern.match(content, cursor)
          return [content, cursor] unless match

          rewritten = "#{match[1]}#{new_version}"
          updated = T.must(content[0...match.begin(0)]) + rewritten + T.must(content[match.end(0)..])
          [updated, match.begin(0) + rewritten.length]
        end

        # Wrap a requirement in double quotes when it would otherwise be
        # ambiguous as a YAML plain scalar: any whitespace, or a leading
        # YAML-indicator character (">", "<", "~", "|", etc.). Simple values
        # (exact, caret) are left bare, preserving the previous output.
        sig { params(value: String).returns(String) }
        def yaml_safe_value(value)
          return "\"#{value}\"" if value.match?(/\s/) || value.match?(/\A[>~<|&*!%@?:#,\[\]{}]/)

          value
        end

        # The strategy-updated requirement string for a specific chart entry,
        # matched by the entry's authored version (source[:tag]) so repeated
        # occurrences of the same chart name each get their own update. Falls
        # back to the first requirement for the file, then to nil (exact pin).
        sig { params(file: Dependabot::DependencyFile, old_version: String).returns(T.nilable(String)) }
        def updated_requirement_string(file, old_version)
          reqs = dependency.requirements.select do |r|
            r[:file] == file.name && r.dig(:metadata, :type) == :helm_chart
          end
          req = reqs.find { |r| r.dig(:source, :tag) == old_version } || reqs.first
          req && req[:requirement]
        end

        sig { params(file: Dependabot::DependencyFile).returns(T::Boolean) }
        def update_chart_dependency?(file)
          reqs = dependency.requirements.select { |r| r[:file] == file.name }
          reqs.any? { |r| r[:metadata]&.dig(:type) == :helm_chart }
        end
      end
    end
  end
end
