# typed: strict
# frozen_string_literal: true

require "dependabot/package/release_cooldown_options"
require "dependabot/maven/file_parser"
require "dependabot/maven/update_checker"
require "dependabot/maven/file_updater/declaration_finder"
require "sorbet-runtime"

module Dependabot
  module Maven
    class UpdateChecker
      class PropertyUpdater
        extend T::Sig

        require_relative "requirements_updater"
        require_relative "version_finder"

        sig do
          params(
            dependency: Dependabot::Dependency,
            dependency_files: T::Array[Dependabot::DependencyFile],
            credentials: T::Array[Dependabot::Credential],
            ignored_versions: T::Array[String],
            target_version_details: T.nilable(UpdateChecker::VersionDetails),
            update_cooldown: T.nilable(Dependabot::Package::ReleaseCooldownOptions)
          ).void
        end
        def initialize(
          dependency:,
          dependency_files:,
          credentials:,
          ignored_versions:,
          target_version_details:,
          update_cooldown: nil
        )
          @dependency       = dependency
          @dependency_files = dependency_files
          @credentials      = credentials
          @ignored_versions = ignored_versions
          target_version = target_version_details&.fetch(:version)
          target_version = nil unless target_version.is_a?(Dependabot::Maven::Version)
          @target_version = T.let(target_version, T.nilable(Dependabot::Maven::Version))
          @source_url = T.let(target_version_details&.fetch(:source_url), T.nilable(String))
          @update_cooldown = update_cooldown
          @property_value_finder = T.let(nil, T.nilable(Dependabot::Maven::FileParser::PropertyValueFinder))
        end

        sig { returns(T::Boolean) }
        def update_possible?
          return false unless target_version
          return T.must(@update_possible) if defined?(@update_possible)

          @update_possible ||= T.let(
            dependencies_using_property.all? do |dep|
              # Skip the property update when a dependency sharing the property has no
              # locatable inline version to rewrite (e.g. a version managed by an
              # imported BOM), since the update cannot be applied to it.
              next false if version_string(dep).nil?

              next false if includes_property_reference?(updated_version(dep))
              next false unless writable_requirements?(dep)

              release_available?(dep, updated_version(dep))
            end,
            T.nilable(T::Boolean)
          )
        end

        sig { returns(T::Array[Dependabot::Dependency]) }
        def updated_dependencies
          raise "Update not possible!" unless update_possible?

          @updated_dependencies ||= T.let(
            dependencies_using_property.map do |dep|
              Dependency.new(
                name: dep.name,
                version: updated_version(dep),
                requirements: updated_requirements(dep),
                previous_version: previous_version(dep),
                previous_requirements: dep.requirements,
                package_manager: dep.package_manager
              )
            end,
            T.nilable(T::Array[Dependabot::Dependency])
          )
        end

        private

        sig { returns(Dependabot::Dependency) }
        attr_reader :dependency

        sig { returns(T::Array[Dependabot::DependencyFile]) }
        attr_reader :dependency_files

        sig { returns(T.nilable(Dependabot::Maven::Version)) }
        attr_reader :target_version

        sig { returns(T.nilable(String)) }
        attr_reader :source_url

        sig { returns(T::Array[Dependabot::Credential]) }
        attr_reader :credentials

        sig { returns(T::Array[String]) }
        attr_reader :ignored_versions

        sig { returns(T.nilable(Dependabot::Package::ReleaseCooldownOptions)) }
        attr_reader :update_cooldown

        sig { returns(T::Array[Dependabot::Dependency]) }
        def dependencies_using_property
          @dependencies_using_property ||= T.let(
            parsed_dependencies.select do |dep|
              dep.requirements.any? { |requirement| uses_property?(requirement) }
            end,
            T.nilable(T::Array[Dependabot::Dependency])
          )
        end

        sig { returns(T::Array[Dependabot::Dependency]) }
        def parsed_dependencies
          @parsed_dependencies ||= T.let(
            Maven::FileParser.new(
              dependency_files: dependency_files,
              source: nil,
              options: { skip_dependency_tree: true }
            ).parse,
            T.nilable(T::Array[Dependabot::Dependency])
          )
        end

        sig { returns(String) }
        def property_name
          @property_name ||= T.let(
            property_requirement.metadata_string("property_name"),
            T.nilable(String)
          )

          raise "No requirement with a property name!" unless @property_name

          @property_name
        end

        sig { returns(T.nilable(String)) }
        def property_source
          @property_source ||= T.let(
            property_requirement.metadata_string("property_source"),
            T.nilable(String)
          )
        end

        sig { returns(Dependabot::DependencyRequirement) }
        def property_requirement
          property_requirements = dependency.requirements.select { |r| r.metadata_string("property_name") }
          matching_requirement = property_requirements.find do |requirement|
            normalized_requirement_version(requirement) == dependency.version
          end
          requirement = matching_requirement || property_requirements.first

          raise "No requirement with a property name!" unless requirement

          requirement
        end

        sig { params(requirement: Dependabot::DependencyRequirement).returns(T.nilable(String)) }
        def normalized_requirement_version(requirement)
          requirement_string = requirement.requirement_string
          return unless requirement_string
          return if requirement_string.include?(",")

          requirement_string.gsub(/[\(\)\[\]]/, "").strip
        end

        sig { params(string: String).returns(T::Boolean) }
        def includes_property_reference?(string)
          string.match?(Maven::FileParser::PROPERTY_REGEX)
        end

        sig { params(dep: Dependabot::Dependency).returns(T.nilable(String)) }
        def version_string(dep)
          declared_version_string(dep, declaring_property_requirement(dep))
        end

        sig do
          params(
            dep: Dependabot::Dependency,
            declaring_requirement: Dependabot::DependencyRequirement
          ).returns(T.nilable(String))
        end
        def declared_version_string(dep, declaring_requirement)
          Maven::FileUpdater::DeclarationFinder.new(
            dependency: dep,
            declaring_requirement: declaring_requirement,
            dependency_files: dependency_files
          ).declaration_nodes.first&.at_css("version")&.content
        end

        sig { params(dep: Dependabot::Dependency, version: String, cache_key: String).returns(T::Boolean) }
        def release_available?(dep, version, cache_key: dep.name)
          @release_versions ||= T.let({}, T.nilable(T::Hash[String, T::Array[Dependabot::Version]]))
          versions = @release_versions[cache_key] ||=
            VersionFinder.new(
              dependency: dep,
              dependency_files: dependency_files,
              credentials: credentials,
              ignored_versions: ignored_versions,
              security_advisories: [],
              cooldown_options: update_cooldown
            ).releases.map(&:version)

          versions.include?(version) || versions.none?
        end

        sig { returns(T.nilable(Dependabot::DependencyFile)) }
        def pom
          dependency_files.find { |f| f.name == "pom.xml" }
        end

        sig { params(dep: Dependabot::Dependency).returns(String) }
        def updated_version(dep)
          unless target_version
            raise "Cannot update property: target version is nil. " \
                  "This may indicate an issue with version resolution for dependency #{dep.name}"
          end

          T.must(version_string(dep)).gsub("${#{property_name}}", T.must(target_version).to_s)
        end

        sig { params(dep: Dependabot::Dependency).returns(String) }
        def previous_version(dep)
          T.must(version_string(dep)).gsub("${#{property_name}}", current_property_value(dep))
        end

        sig { params(dep: Dependabot::Dependency).returns(String) }
        def current_property_value(dep)
          declaring_requirement = declaring_property_requirement(dep)
          callsite_pom = dependency_files.find { |f| f.name == declaring_requirement.file }
          unless callsite_pom
            raise DependencyFileNotEvaluatable,
                  "POM not found: #{declaring_requirement.file} for property #{property_name}"
          end

          property_value =
            property_value_finder
            .property_details(property_name: property_name, callsite_pom: callsite_pom)
            &.fetch(:value)

          return property_value if property_value.is_a?(String)

          raise DependencyFileNotEvaluatable, "Property not found: #{property_name}"
        end

        sig { params(dep: Dependabot::Dependency).returns(Dependabot::DependencyRequirement) }
        def declaring_property_requirement(dep)
          declaring_requirement =
            dep.requirements.find { |requirement| same_property_source?(requirement) } ||
            dep.requirements.find { |requirement| uses_property?(requirement) }

          return declaring_requirement if declaring_requirement

          raise DependencyFileNotEvaluatable,
                "Requirement not found for property #{property_name} from #{property_source || 'unknown source'}"
        end

        sig { params(requirement: Dependabot::DependencyRequirement).returns(T::Boolean) }
        def uses_property?(requirement)
          return true if same_property_source?(requirement)

          requirement.metadata_string("property_name") == property_name &&
            linked_property_sources.include?(requirement.metadata_string("property_source"))
        end

        # Sibling modules often define the same property with the same value.
        # Update them together so the modules stay in sync.
        sig { returns(T::Array[String]) }
        def linked_property_sources
          @linked_property_sources ||= T.let(
            parsed_dependencies
              .flat_map(&:requirements)
              .select { |requirement| requirement.metadata_string("property_name") == property_name }
              .group_by { |requirement| requirement.metadata_string("property_source") }
              .select { |source, requirements| linkable_property_source?(source, requirements) }
              .keys.compact,
            T.nilable(T::Array[String])
          )
        end

        sig do
          params(
            source: T.nilable(String),
            requirements: T::Array[Dependabot::DependencyRequirement]
          ).returns(T::Boolean)
        end
        def linkable_property_source?(source, requirements)
          return false if source.nil? || source == property_source
          return false unless dependency_files.any? { |f| f.name == source }

          selected_value = property_value_at(property_requirement.file)
          return false if selected_value.nil?
          # A suffixed use in the selected module also writes a suffixed value, so don't link any module then.
          return false unless plain_property_uses?(selected_property_requirements, selected_value)

          # Skip the module if any declaration there adds to the value (e.g.
          # `${prop}-ext`): the property would be written with that version.
          plain_values = plain_property_uses?(requirements, selected_value)

          # Only the selected module may block the update; skip a linked module that can't be updated.
          plain_values &&
            only_dependency_property_references?(source) &&
            parsed_dependencies.all? { |dep| linked_dependency_updatable?(dep, source) }
        end

        # Every `${prop}` resolved from the source must be a parsed dependency version. Other uses (e.g.
        # `${prefix}${prop}` or `<other.version>${prop}-ext</other.version>`) would change without a check.
        sig { params(source: String).returns(T::Boolean) }
        def only_dependency_property_references?(source)
          reference = "${#{property_name}}"
          dependency_files.all? do |file|
            content = file.content.to_s
            next true unless content.include?(reference)
            next true unless property_value_finder.property_details(
              property_name: property_name, callsite_pom: file
            )&.fetch(:file) == source

            parsed_uses = parsed_dependencies.flat_map(&:requirements).count do |requirement|
              requirement.file == file.name && requirement.metadata_string("property_name") == property_name
            end
            content.scan(reference).length == parsed_uses
          end
        end

        sig { params(dep: Dependabot::Dependency, source: String).returns(T::Boolean) }
        def linked_dependency_updatable?(dep, source)
          requirement = dep.requirements.find do |req|
            req.metadata_string("property_name") == property_name && req.metadata_string("property_source") == source
          end
          return true unless requirement
          return false unless property_only_dependency?(dep)

          new_version = declared_version_string(dep, requirement)&.gsub("${#{property_name}}", target_version.to_s)
          return false if new_version.nil? || includes_property_reference?(new_version)

          # Look up releases with this module's repositories.
          module_dependency = Dependabot::Dependency.new(
            name: dep.name, version: dep.version, requirements: [requirement], package_manager: dep.package_manager
          )
          release_available?(module_dependency, new_version, cache_key: "#{dep.name}@#{requirement.file}")
        rescue Dependabot::DependabotError => e
          Dependabot.logger.info("Not updating #{property_name} in #{source}: #{e.message}")
          false
        end

        # A dependency only reached through a linked module must not change declarations that don't use the property.
        sig { params(dep: Dependabot::Dependency).returns(T::Boolean) }
        def property_only_dependency?(dep)
          dep.requirements.any? { |req| same_property_source?(req) } ||
            dep.requirements.all? { |req| req.metadata_string("property_name") == property_name }
        end

        sig { returns(T::Array[Dependabot::DependencyRequirement]) }
        def selected_property_requirements
          @selected_property_requirements ||= T.let(
            parsed_dependencies.flat_map(&:requirements).select { |requirement| same_property_source?(requirement) },
            T.nilable(T::Array[Dependabot::DependencyRequirement])
          )
        end

        sig do
          params(
            requirements: T::Array[Dependabot::DependencyRequirement],
            value: String
          ).returns(T::Boolean)
        end
        def plain_property_uses?(requirements, value)
          requirements.all? do |requirement|
            requirement.requirement == value && property_value_at(requirement.file) == value
          end
        end

        sig { params(requirement: Dependabot::DependencyRequirement).returns(T::Boolean) }
        def same_property_source?(requirement)
          requirement.metadata_string("property_name") == property_name &&
            requirement.metadata_string("property_source") == property_source
        end

        sig { params(callsite_file: T.nilable(String)).returns(T.nilable(String)) }
        def property_value_at(callsite_file)
          return unless callsite_file

          @property_values ||= T.let({}, T.nilable(T::Hash[String, T.nilable(String)]))
          return @property_values[callsite_file] if @property_values.key?(callsite_file)

          callsite_pom = dependency_files.find { |f| f.name == callsite_file }
          value =
            if callsite_pom
              property_value_finder
                .property_details(property_name: property_name, callsite_pom: callsite_pom)
                &.fetch(:value)
            end
          @property_values[callsite_file] = value.is_a?(String) ? value : nil
        end

        sig { params(dep: Dependabot::Dependency).returns(T::Array[Dependabot::DependencyRequirement]) }
        def updated_requirements(dep)
          @updated_requirements ||= T.let({}, T.nilable(T::Hash[String, T::Array[Dependabot::DependencyRequirement]]))
          @updated_requirements[dep.name] ||=
            RequirementsUpdater.new(
              requirements: dep.requirements,
              latest_version: updated_version(dep),
              source_url: source_url,
              properties_to_update: [property_name]
            ).updated_requirements.map.with_index do |requirement, index|
              original = dep.requirements.fetch(index)
              next requirement unless original.metadata_string("property_name")

              uses_property?(original) ? requirement : original
            end
        end

        sig { params(dep: Dependabot::Dependency).returns(T::Boolean) }
        def writable_requirements?(dep)
          updated = updated_requirements(dep)
          writable = dep.requirements.each_with_index.any? do |requirement, index|
            uses_property?(requirement) && updated.fetch(index).requirement != requirement.requirement
          end
          return true if writable

          Dependabot.logger.info(
            "Cannot update shared property #{property_name}: no writable requirement changes for #{dep.name}"
          )
          false
        end

        sig { returns(Dependabot::Maven::FileParser::PropertyValueFinder) }
        def property_value_finder
          @property_value_finder ||=
            Dependabot::Maven::FileParser::PropertyValueFinder.new(
              dependency_files: dependency_files,
              credentials: credentials
            )
        end
      end
    end
  end
end
