# frozen_string_literal: true

require "dependabot/dependency"
require "dependabot/file_parsers/base"
require "dependabot/utils"

module Dependabot
  module FileParsers
    class Base
      class DependencySet
        def initialize(dependencies = [], case_sensitive: false)
          unless dependencies.is_a?(Array) &&
                 dependencies.all?(Dependency)
            raise ArgumentError, "must be an array of Dependency objects"
          end

          @case_sensitive = case_sensitive
          @dependencies = Hash.new { |hsh, key| hsh[key] = DependencySlot.new }
          dependencies.each { |dep| self << dep }
        end

        def dependencies
          @dependencies.values.filter_map(&:combined)
        end

        def <<(dep)
          raise ArgumentError, "must be a Dependency object" unless dep.is_a?(Dependency)

          @dependencies[key_for_dependency(dep)] << dep
          self
        end

        def +(other)
          raise ArgumentError, "must be a DependencySet" unless other.is_a?(DependencySet)

          other_names = other.dependencies.map(&:name)
          other_names.each do |name|
            all_versions = other.all_versions_for_name(name)
            all_versions.each { |dep| self << dep }
          end

          self
        end

        def all_versions_for_name(name)
          key = key_for_name(name)
          @dependencies.key?(key) ? @dependencies[key].all_versions : []
        end

        def dependency_for_name(name)
          key = key_for_name(name)
          @dependencies.key?(key) ? @dependencies[key].combined : nil
        end

        private

        def case_sensitive?
          @case_sensitive
        end

        def key_for_name(name)
          case_sensitive? ? name : name.downcase
        end

        def key_for_dependency(dep)
          key_for_name(dep.name)
        end

        # There can only be one entry per dependency name in a `DependencySet`. Each entry
        # is assigned a `DependencySlot`.
        #
        # In some ecosystems (like `npm_and_yarn`), however, multiple versions of a
        # dependency may be encountered and added to the set. The `DependencySlot` retains
        # all added versions and presents a single unified dependency for the entry
        # that combines the attributes of these versions.
        #
        # The combined dependency is accessible via `DependencySet#dependencies` or
        # `DependencySet#dependency_for_name`. The list of individual versions of the
        # dependency is accessible via `DependencySet#all_versions_for_name`.
        class DependencySlot
          attr_reader :all_versions, :combined

          def initialize
            @all_versions = []
            @combined = nil
          end

          def <<(dep)
            return self if @all_versions.include?(dep)

            @combined = if @combined
                          combined_dependency(@combined, dep)
                        else
                          Dependency.new(
                            name: dep.name,
                            version: dep.version,
                            requirements: dep.requirements,
                            package_manager: dep.package_manager,
                            subdependency_metadata: dep.subdependency_metadata
                          )
                        end

            index_of_same_version =
              @all_versions.find_index { |other| other.version == dep.version }

            if index_of_same_version.nil?
              @all_versions << dep
            else
              same_version = @all_versions[index_of_same_version]
              @all_versions[index_of_same_version] = combined_dependency(same_version, dep)
            end

            self
          end

          private

          # Produces a new dependency by merging the attributes of `old_dep` with those of
          # `new_dep`. Requirements and subdependency metadata will be combined and deduped.
          # The version of the combined dependency is determined by the
          # `#combined_version` method below.
          def combined_dependency(old_dep, new_dep)
            version = combined_version(old_dep, new_dep)
            requirements = (old_dep.requirements + new_dep.requirements).uniq
            subdependency_metadata = (
              (old_dep.subdependency_metadata || []) +
              (new_dep.subdependency_metadata || [])
            ).uniq

            Dependency.new(
              name: old_dep.name,
              version: version,
              requirements: requirements,
              package_manager: old_dep.package_manager,
              subdependency_metadata: subdependency_metadata
            )
          end

          def combined_version(old_dep, new_dep)
            if old_dep.version.nil? ^ new_dep.version.nil?
              [old_dep, new_dep].find(&:version).version
            elsif old_dep.top_level? ^ new_dep.top_level? # Prefer a direct dependency over a transitive one
              [old_dep, new_dep].find(&:top_level?).version
            elsif !version_class.correct?(new_dep.version)
              old_dep.version
            elsif !version_class.correct?(old_dep.version)
              new_dep.version
            elsif version_class.new(new_dep.version) > version_class.new(old_dep.version)
              old_dep.version
            else
              new_dep.version
            end
          end

          def version_class
            @version_class ||= Utils.version_class_for_package_manager(@combined.package_manager)
          end
        end
        private_constant :DependencySlot
      end
    end
  end
end
