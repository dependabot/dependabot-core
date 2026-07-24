# typed: strict
# frozen_string_literal: true

require "sorbet-runtime"
require "dependabot/dependency_requirement"
require "dependabot/powershell/file_updater"
require "dependabot/powershell/file_updater/declaration_locator"

module Dependabot
  module Powershell
    class FileUpdater < Dependabot::FileUpdaters::Base
      # Rewrites the version-bearing key(s) of module declarations in a
      # single dependency file so its content reflects each dependency's
      # updated requirement, while leaving everything else - GUID, unrelated
      # keys, quote style, whitespace, bare string declarations with no
      # version constraint - exactly as originally written.
      class DeclarationRewriter
        extend T::Sig

        # Maps a requirement's `version_key` (set by the stage-3 parser) to
        # the hashtable field whose value must be rewritten. A
        # ModuleVersion+MaximumVersion range only ever has its upper bound
        # raised (see UpdateChecker::RequirementsUpdater#bump_range_maximum),
        # so both the bare MaximumVersion case and the combined range case
        # target the same field.
        VERSION_FIELDS = T.let(
          {
            "RequiredVersion" => "RequiredVersion",
            "ModuleVersion" => "ModuleVersion",
            "MaximumVersion" => "MaximumVersion",
            "ModuleVersion+MaximumVersion" => "MaximumVersion"
          }.freeze,
          T::Hash[String, String]
        )

        # A single content replacement: replace content[start_index...end_index]
        # with replacement_text.
        Edit = T.type_alias { [Integer, Integer, String] }

        sig { params(file: Dependabot::DependencyFile, dependencies: T::Array[Dependabot::Dependency]).void }
        def initialize(file:, dependencies:)
          @file = file
          @dependencies = dependencies
        end

        sig { returns(String) }
        def updated_content
          content = T.must(@file.content)
          edits = collect_edits(content)
          return content if edits.empty?

          apply_edits(content, edits)
        end

        private

        sig { returns(Dependabot::DependencyFile) }
        attr_reader :file

        sig { returns(T::Array[Dependabot::Dependency]) }
        attr_reader :dependencies

        sig { params(content: String).returns(T::Array[Edit]) }
        def collect_edits(content)
          occurrences_by_name = DeclarationLocator.new(file: file).locate.group_by { |occ| occ.name.downcase }
          return [] if occurrences_by_name.empty?

          dependencies.flat_map { |dependency| edits_for_dependency(dependency, occurrences_by_name, content) }
        end

        sig do
          params(
            dependency: Dependabot::Dependency,
            occurrences_by_name: T::Hash[String, T::Array[DeclarationLocator::Occurrence]],
            content: String
          ).returns(T::Array[Edit])
        end
        def edits_for_dependency(dependency, occurrences_by_name, content)
          occurrences = occurrences_by_name[dependency.name.downcase]
          return [] unless occurrences

          previous_requirements = requirements_for_file(dependency.previous_requirements)
          current_requirements = requirements_for_file(dependency.requirements)

          changes = requirement_changes(previous_requirements, current_requirements)
          return [] if changes.empty?

          occurrences.filter_map { |occurrence| edit_for_matching_occurrence(occurrence, changes, content) }
        end

        # Pairs each previous requirement with its updated counterpart (both
        # arrays come from `RequirementsUpdater#updated_requirements`, which
        # maps 1:1 over its input, so index-based pairing between them is
        # safe), keeping only the pairs whose requirement string changed.
        sig do
          params(
            previous_requirements: T::Array[Dependabot::DependencyRequirement],
            current_requirements: T::Array[Dependabot::DependencyRequirement]
          ).returns(T::Array[[Dependabot::DependencyRequirement, String]])
        end
        def requirement_changes(previous_requirements, current_requirements)
          current_requirements.each_with_index.filter_map do |current, index|
            previous = previous_requirements[index]
            next unless previous
            next if current.requirement == previous.requirement

            new_requirement = current.requirement
            next unless new_requirement.is_a?(String)

            [previous, new_requirement]
          end
        end

        sig do
          params(
            requirements: T.nilable(T::Array[Dependabot::DependencyRequirement])
          ).returns(T::Array[Dependabot::DependencyRequirement])
        end
        def requirements_for_file(requirements)
          (requirements || []).select { |requirement| requirement.file == file.name }
        end

        sig do
          params(
            occurrence: DeclarationLocator::Occurrence,
            changes: T::Array[[Dependabot::DependencyRequirement, String]],
            content: String
          ).returns(T.nilable(Edit))
        end
        def edit_for_matching_occurrence(occurrence, changes, content)
          return nil unless occurrence.style == :hashtable

          field = VERSION_FIELDS[occurrence.version_key]
          return nil unless field

          value_span = value_span_for(content, occurrence, field)
          return nil unless value_span

          current_value = content[value_span[0]...value_span[1]]

          # Duplicate identical declarations collapse into a single
          # requirement change upstream (see DependencySet#combined_dependency),
          # so more than one occurrence can legitimately match the same
          # change here - each still gets its own edit, keyed by whatever
          # version is actually on disk for it rather than by position.
          match = changes.find do |previous, _|
            extract_version(previous.requirement, occurrence.version_key) == current_value
          end
          return nil unless match

          new_value = extract_version(match[1], occurrence.version_key)
          return nil unless new_value

          [value_span[0], value_span[1], new_value]
        end

        # Extracts the version literal that `version_key` binds to from a
        # requirement string built by UpdateChecker::RequirementsUpdater
        # (e.g. "= X", ">= X", "<= X", or ">= X, <= Y").
        sig { params(requirement_string: String, version_key: T.nilable(String)).returns(T.nilable(String)) }
        def extract_version(requirement_string, version_key)
          case version_key
          when "RequiredVersion"
            requirement_string.delete_prefix("=").strip
          when "ModuleVersion"
            requirement_string.delete_prefix(">=").strip
          when "MaximumVersion"
            requirement_string.delete_prefix("<=").strip
          when "ModuleVersion+MaximumVersion"
            constraint = requirement_string.split(",").map(&:strip).find { |c| c.start_with?("<=") }
            constraint&.delete_prefix("<=")&.strip
          end
        end

        # Finds the quoted value of `field` within the occurrence's raw
        # hashtable text and returns its absolute [start, end) offsets
        # within `content`, so only that value - not the key, quote
        # characters, GUID, or any other field - gets replaced.
        sig do
          params(
            content: String,
            occurrence: DeclarationLocator::Occurrence,
            field: String
          ).returns(T.nilable([Integer, Integer]))
        end
        def value_span_for(content, occurrence, field)
          raw = content[occurrence.start_index...occurrence.end_index]
          return nil unless raw

          # Blank out `# ...` line comments (preserving length and quoted
          # strings) before matching, so a commented-out field - e.g.
          # `# RequiredVersion = '1.0.0'` sitting before the active
          # field - can't be matched instead of the real one. Offsets stay
          # aligned with `raw` (and therefore `content`) since comment text
          # is replaced character-for-character.
          scannable = blank_line_comments(raw)

          pattern = /#{Regexp.escape(field)}\s*=\s*(?<quote>['"])(?<value>[^'"]*)\k<quote>/i
          match = pattern.match(scannable)
          return nil unless match

          value_start = occurrence.start_index + T.must(match.begin(:value))
          value_end = occurrence.start_index + T.must(match.end(:value))
          [value_start, value_end]
        end

        # Replaces `# ...` line comments in `text` with equal-length spaces
        # (newlines preserved), respecting quoted strings (which may
        # themselves contain a `#`), so the returned string is the same
        # length as `text` - keeping offsets found within it valid against
        # `text` - but comment text can no longer match a field pattern.
        sig { params(text: String).returns(String) }
        def blank_line_comments(text)
          result = +""
          quote = T.let(nil, T.nilable(String))
          in_comment = T.let(false, T::Boolean)

          text.each_char do |char|
            if in_comment
              if char == "\n"
                in_comment = false
                result << char
              else
                result << " "
              end
              next
            end

            if quote
              result << char
              quote = nil if char == quote
              next
            end

            case char
            when "'", "\""
              quote = char
              result << char
            when "#"
              in_comment = true
              result << " "
            else
              result << char
            end
          end

          result
        end

        sig { params(content: String, edits: T::Array[Edit]).returns(String) }
        def apply_edits(content, edits)
          result = content.dup
          edits.sort_by { |edit| -edit[0] }.each do |start_index, end_index, replacement|
            result[start_index...end_index] = replacement
          end
          result
        end
      end
    end
  end
end
