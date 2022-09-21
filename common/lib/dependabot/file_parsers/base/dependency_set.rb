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

          @dependencies[key_for(dep)] << dep
          self
        end

        def +(other)
          raise ArgumentError, "must be a DependencySet" unless other.is_a?(DependencySet)

          other.dependencies.each { |dep| self << dep }
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

        def key_for(dep)
          key_for_name(dep.name)
        end

        class DependencySlot
          attr_reader :all_versions, :combined

          def initialize
            @all_versions = []
            @combined = nil
          end

          def <<(dep)
            return self if @all_versions.include?(dep)

            @combined = if @combined
                          combine(@combined, dep)
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
              @all_versions[index_of_same_version] = combine(same_version, dep)
            end

            sort!

            self
          end

          private

          def combine(old_dep, new_dep)
            version = if old_dep.requirements.any?
                        old_dep.version || new_dep.version
                      elsif !version_class.correct?(new_dep.version)
                        old_dep.version
                      elsif !version_class.correct?(old_dep.version)
                        new_dep.version
                      elsif version_class.new(new_dep.version) > version_class.new(old_dep.version)
                        old_dep.version
                      else
                        new_dep.version
                      end
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

          def sort!
            @all_versions.sort! do |a, b|
              a_ok = version_class.correct?(a.version)
              b_ok = version_class.correct?(b.version)

              next version_class.new(a.version) <=> version_class.new(b.version) if a_ok && b_ok
              next 1 if b_ok
              next -1 if a_ok

              0
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
