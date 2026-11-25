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
      class PropertyUpdater # rubocop:disable Metrics/ClassLength
        extend T::Sig

        require_relative "requirements_updater"
        require_relative "transitive_overrides"
        require_relative "version_finder"

        sig do
          params(
            dependency: Dependabot::Dependency,
            dependency_files: T::Array[Dependabot::DependencyFile],
            credentials: T::Array[Dependabot::Credential],
            ignored_versions: T::Array[String],
            target_version_details: T.nilable(UpdateChecker::VersionDetails),
            update_cooldown: T.nilable(Dependabot::Package::ReleaseCooldownOptions),
            security_update: T::Boolean
          ).void
        end
        def initialize(
          dependency:,
          dependency_files:,
          credentials:,
          ignored_versions:,
          target_version_details:,
          update_cooldown: nil,
          security_update: false
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
          @security_update = security_update
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
              # Dependencies only reached through a linked module were already checked with that module's POM.
              next true if dep.requirements.none? { |requirement| same_property_source?(requirement) }

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
          property_requirements = TransitiveOverrides.raisable_property_requirements(
            dependency.requirements, security_update: @security_update
          ) { parsed_dependencies }
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

        sig { params(dep: Dependabot::Dependency, version: String).returns(T::Boolean) }
        def release_available?(dep, version)
          versions = release_versions(dep, cache_key: dep.name)
          versions.include?(version) || versions.none?
        end

        # Releases are looked up with the repositories of the POM of the dependency's first requirement.
        sig { params(dep: Dependabot::Dependency, cache_key: String).returns(T::Array[Dependabot::Version]) }
        def release_versions(dep, cache_key:)
          @release_versions ||= T.let({}, T.nilable(T::Hash[String, T::Array[Dependabot::Version]]))
          @release_versions[cache_key] ||=
            VersionFinder.new(
              dependency: dep,
              dependency_files: dependency_files,
              credentials: credentials,
              ignored_versions: ignored_versions,
              security_advisories: [],
              cooldown_options: update_cooldown
            ).releases.map(&:version)
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

          selected_value = linkable_selected_value
          return false if selected_value.nil?

          # Skip the module if any declaration there adds to the value (e.g.
          # `${prop}-ext`): the property would be written with that version.
          # Only the selected module may block the update; skip a linked module that can't be updated.
          raisable_linked_requirements?(requirements) &&
            plain_property_uses?(requirements, selected_value) &&
            only_dependency_property_references?(source) &&
            parsed_dependencies.all? { |dep| linked_dependency_updatable?(dep, source) }
        end

        # A suffixed use in the selected module also writes a suffixed value, so don't link any module then.
        sig { returns(T.nilable(String)) }
        def linkable_selected_value
          selected_value = property_value_at(property_requirement.file)
          return if selected_value.nil?

          selected_value if plain_property_uses?(selected_property_requirements, selected_value)
        end

        # Outside a security update, a property that only transitive overrides use is never raised.
        sig { params(requirements: T::Array[Dependabot::DependencyRequirement]).returns(T::Boolean) }
        def raisable_linked_requirements?(requirements)
          @security_update || requirements.any? { |requirement| !TransitiveOverrides.override?(requirement) }
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

            content.scan(reference).length == property_declaration_count(file)
          end
        end

        # Counts declarations, since identical requirements (e.g. the same dependency in
        # dependencyManagement and dependencies) are merged when parsed. Requirements that
        # differ only in metadata the XML match ignores (e.g. the override tag) find the same
        # declarations, so they're counted once.
        sig { params(file: Dependabot::DependencyFile).returns(Integer) }
        def property_declaration_count(file)
          parsed_dependencies.sum do |dep|
            requirements = dep.requirements.select do |requirement|
              requirement.file == file.name && requirement.metadata_string("property_name") == property_name
            end
            requirements.uniq { |requirement| Maven::FileUpdater::DeclarationFinder.match_key(requirement) }
                        .sum do |requirement|
              Maven::FileUpdater::DeclarationFinder.new(
                dependency: dep,
                declaring_requirement: requirement,
                dependency_files: dependency_files
              ).declaration_strings.length
            end
          end
        end

        sig { params(dep: Dependabot::Dependency, source: String).returns(T::Boolean) }
        def linked_dependency_updatable?(dep, source)
          requirements = dep.requirements.select do |req|
            req.metadata_string("property_name") == property_name && req.metadata_string("property_source") == source
          end
          return true if requirements.empty?
          return false unless property_only_dependency?(dep)

          # Each POM that inherits the property may resolve the dependency from different repositories,
          # including versionless consumers that take the version from the source's dependencyManagement.
          new_version = linked_new_version(dep, requirements)
          return false if new_version.nil?

          (requirements + versionless_consumers(dep, source)).all? do |requirement|
            linked_release_listed?(dep, requirement, new_version)
          end
        rescue Dependabot::DependabotError => e
          Dependabot.logger.info("Not updating #{property_name} in #{source}: #{e.message}")
          false
        end

        sig do
          params(
            dep: Dependabot::Dependency,
            requirements: T::Array[Dependabot::DependencyRequirement]
          ).returns(T.nilable(String))
        end
        def linked_new_version(dep, requirements)
          new_versions = requirements.map do |requirement|
            declared_version_string(dep, requirement)&.gsub("${#{property_name}}", target_version.to_s)
          end
          return if new_versions.any? { |version| version.nil? || includes_property_reference?(version) }

          new_versions.first
        end

        sig { params(dep: Dependabot::Dependency, source: String).returns(T::Array[Dependabot::DependencyRequirement]) }
        def versionless_consumers(dep, source)
          dep.requirements.select do |requirement|
            next false unless requirement.requirement.nil? && requirement.file

            property_source_for(T.must(requirement.file)) == source
          end
        end

        sig { params(file_name: String).returns(T.nilable(String)) }
        def property_source_for(file_name)
          callsite_pom = dependency_files.find { |f| f.name == file_name }
          return unless callsite_pom

          source = property_value_finder.property_details(property_name: property_name, callsite_pom: callsite_pom)
                                        &.fetch(:file)
          source.is_a?(String) ? source : nil
        end

        # Unlike the selected module, a linked module needs its repositories to list the new version.
        sig do
          params(
            dep: Dependabot::Dependency,
            requirement: Dependabot::DependencyRequirement,
            new_version: String
          ).returns(T::Boolean)
        end
        def linked_release_listed?(dep, requirement, new_version)
          module_dependency = Dependabot::Dependency.new(
            name: dep.name, version: dep.version, requirements: [requirement], package_manager: dep.package_manager
          )
          release_versions(module_dependency, cache_key: "#{dep.name}@#{requirement.file}").include?(new_version)
        end

        # A dependency only reached through a linked module must not change declarations that don't use the
        # property. Versionless consumers have nothing to rewrite, so they don't count.
        sig { params(dep: Dependabot::Dependency).returns(T::Boolean) }
        def property_only_dependency?(dep)
          dep.requirements.any? { |req| same_property_source?(req) } ||
            dep.requirements.all? do |req|
              req.requirement.nil? || req.metadata_string("property_name") == property_name
            end
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
              next original if keep_unchanged?(dep, original)
              next requirement unless original.metadata_string("property_name")

              uses_property?(original) ? requirement : original
            end
        end

        # A literal transitive override isn't tied to the shared property, so the property update leaves
        # it, and any declaration whose rewrite would also hit it, alone. Only a security update raises
        # it, and only for the vulnerable dependency.
        sig { params(dep: Dependabot::Dependency, requirement: Dependabot::DependencyRequirement).returns(T::Boolean) }
        def keep_unchanged?(dep, requirement)
          return false if @security_update && dep.name == dependency.name
          return false if requirement.metadata_string("property_name")

          TransitiveOverrides.override?(requirement) ||
            TransitiveOverrides.rewrites_an_override?(requirement, dep.requirements)
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
