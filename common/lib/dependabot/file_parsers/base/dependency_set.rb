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

          @dependencies = dependencies
          @case_sensitive = case_sensitive
        end

        attr_reader :dependencies

        def <<(dep)
          raise ArgumentError, "must be a Dependency object" unless dep.is_a?(Dependency)

          existing_dependency = dependency_for_name(dep.name)

          return self if existing_dependency&.to_h == dep.to_h

          if existing_dependency
            dependencies[dependencies.index(existing_dependency)] =
              combined_dependency(existing_dependency, dep)
          else
            dependencies << dep
          end

          self
        end

        def +(other)
          raise ArgumentError, "must be a DependencySet" unless other.is_a?(DependencySet)

          other.dependencies.each { |dep| self << dep }
          self
        end

        private

        def case_sensitive?
          @case_sensitive
        end

        def dependency_for_name(name)
          return dependencies.find { |d| d.name == name } if case_sensitive?

          dependencies.find { |d| d.name&.downcase == name&.downcase }
        end

        def combined_dependency(old_dep, new_dep)
          package_manager = old_dep.package_manager
          v_cls = Utils.version_class_for_package_manager(package_manager)

          # If we already have a requirement use the existing version
          # (if present). Otherwise, use whatever the lowest version is
          new_version =
            if old_dep.requirements.any? then old_dep.version || new_dep.version
            elsif !v_cls.correct?(new_dep.version) then old_dep.version
            elsif !v_cls.correct?(old_dep.version) then new_dep.version
            elsif v_cls.new(new_dep.version) > v_cls.new(old_dep.version)
              old_dep.version
            else
              new_dep.version
            end

          subdependency_metadata = (
            (old_dep.subdependency_metadata || []) +
            (new_dep.subdependency_metadata || [])
          ).uniq

          Dependency.new(
            name: old_dep.name,
            version: new_version,
            requirements: (old_dep.requirements + new_dep.requirements).uniq,
            package_manager: package_manager,
            subdependency_metadata: subdependency_metadata
          )
        end
      end
    end
  end
end
