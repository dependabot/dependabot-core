# typed: strong
# frozen_string_literal: true

require "sorbet-runtime"
require "dependabot/dependency_requirement"
require "dependabot/powershell/file_updater"
require "dependabot/powershell/file_updater/declaration_locator"
require "dependabot/powershell/module_specification_version"

module Dependabot
  module Powershell
    class FileUpdater < Dependabot::FileUpdaters::Base
      # Rewrites the version-bearing key(s) of module declarations in a
      # single dependency file so its content reflects each dependency's
      # updated requirement. A GUID is changed only when the update checker
      # supplies a different GUID for a GUID-qualified exact pin.
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
        RequirementChange = T.type_alias do
          [Dependabot::DependencyRequirement, Dependabot::DependencyRequirement]
        end

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

          occurrences.flat_map { |occurrence| edits_for_matching_occurrence(occurrence, changes, content) }
        end

        # Pairs each previous requirement with its updated counterpart (both
        # arrays come from `RequirementsUpdater#updated_requirements`, which
        # maps 1:1 over its input, so index-based pairing between them is
        # safe), keeping only the pairs whose requirement string changed.
        sig do
          params(
            previous_requirements: T::Array[Dependabot::DependencyRequirement],
            current_requirements: T::Array[Dependabot::DependencyRequirement]
          ).returns(T::Array[RequirementChange])
        end
        def requirement_changes(previous_requirements, current_requirements)
          current_requirements.each_with_index.filter_map do |current, index|
            previous = previous_requirements[index]
            next unless previous
            next if current.requirement == previous.requirement

            next unless current.requirement.is_a?(String)

            [previous, current]
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
            changes: T::Array[RequirementChange],
            content: String
          ).returns(T::Array[Edit])
        end
        def edits_for_matching_occurrence(occurrence, changes, content)
          field = version_field_for(occurrence)
          return [] unless field

          value_span = value_span_for(content, occurrence, field)
          return [] unless value_span

          current_value = content[value_span[0]...value_span[1]]
          return [] unless current_value

          change = matching_change(changes, occurrence.version_key, current_value)
          return [] unless change

          new_value = updated_version(change[1], occurrence.version_key)
          return [] unless new_value

          edits = T.let([[value_span[0], value_span[1], new_value]], T::Array[Edit])
          guid_edit = guid_edit_for(content, occurrence, change[1])
          edits << guid_edit if guid_edit
          edits
        end

        sig { params(occurrence: DeclarationLocator::Occurrence).returns(T.nilable(String)) }
        def version_field_for(occurrence)
          return unless occurrence.style == :hashtable

          version_key = occurrence.version_key
          return unless version_key

          VERSION_FIELDS[version_key]
        end

        # Duplicate identical declarations collapse into a single requirement
        # change upstream, so every matching occurrence must be rewritten.
        sig do
          params(
            changes: T::Array[RequirementChange],
            version_key: T.nilable(String),
            current_value: String
          ).returns(T.nilable(RequirementChange))
        end
        def matching_change(changes, version_key, current_value)
          changes.find do |previous, _|
            previous_requirement = previous.requirement
            next false unless previous_requirement.is_a?(String)

            expected_value = previous_version(previous, version_key)
            next false unless expected_value
            next true if expected_value == current_value

            ModuleSpecificationVersion.compare(expected_value, current_value)&.zero?
          end
        end

        sig do
          params(
            requirement: Dependabot::DependencyRequirement,
            version_key: T.nilable(String)
          ).returns(T.nilable(String))
        end
        def previous_version(requirement, version_key)
          if version_key == "MaximumVersion" || version_key == "ModuleVersion+MaximumVersion"
            maximum_version = requirement.metadata&.fetch(:maximum_version, nil)
            return maximum_version if maximum_version.is_a?(String)
          end

          requirement_string = requirement.requirement
          return unless requirement_string.is_a?(String)

          extract_version(requirement_string, version_key)
        end

        sig do
          params(requirement: Dependabot::DependencyRequirement, version_key: T.nilable(String))
            .returns(T.nilable(String))
        end
        def updated_version(requirement, version_key)
          requirement_string = requirement.requirement
          return unless requirement_string.is_a?(String)

          extract_version(requirement_string, version_key)
        end

        sig do
          params(
            content: String,
            occurrence: DeclarationLocator::Occurrence,
            requirement: Dependabot::DependencyRequirement
          ).returns(T.nilable(Edit))
        end
        def guid_edit_for(content, occurrence, requirement)
          guid = requirement.metadata&.fetch(:updated_guid, nil)
          return unless guid.is_a?(String)

          guid_span = value_span_for(content, occurrence, "GUID")
          return unless guid_span
          return if content[guid_span[0]...guid_span[1]] == guid

          [guid_span[0], guid_span[1], guid]
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

          # Comments are blanked without changing length, so their fields
          # cannot match while offsets remain aligned with the source.
          scannable = ContentMasker.mask(raw)

          # The field name may itself be quoted (e.g. `'ModuleVersion' =
          # '1.0.0'`), just like ModuleSpecificationParser accepts when
          # parsing the same hashtable - so an optional, not-necessarily
          # matching quote character is allowed on either side of it.
          pattern = /['"]?#{Regexp.escape(field)}['"]?\s*=\s*(?<quote>['"])(?<value>[^'"]*)\k<quote>/i
          match = pattern.match(scannable)
          return nil unless match

          value_start = occurrence.start_index + match.begin(:value)
          value_end = occurrence.start_index + match.end(:value)
          [value_start, value_end]
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
