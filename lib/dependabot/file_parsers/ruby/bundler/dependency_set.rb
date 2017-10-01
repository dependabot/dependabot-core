# frozen_string_literal: true

require "dependabot/dependency"
require "dependabot/file_parsers/ruby/bundler"

module Dependabot
  module FileParsers
    module Ruby
      class Bundler
        class DependencySet
          def initialize(dependencies = [])
            unless dependencies.is_a?(Array) &&
                   dependencies.all? { |dep| dep.is_a?(Dependency) }
              raise ArgumentError, "must be an array of Dependency objects"
            end

            @dependencies = dependencies
          end

          attr_reader :dependencies

          def <<(dep)
            unless dep.is_a?(Dependency)
              raise ArgumentError, "must be a Dependency object"
            end

            existing_dependency = dependencies.find { |d| d.name == dep.name }

            if existing_dependency
              return self if existing_dependency.to_h == dep.to_h

              dependencies[dependencies.index(existing_dependency)] =
                Dependency.new(
                  name: existing_dependency.name,
                  version: existing_dependency.version || dep.version,
                  requirements:
                    existing_dependency.requirements + dep.requirements,
                  package_manager: "bundler"
                )
            else
              dependencies << dep
            end
            self
          end

          def +(other)
            unless other.is_a?(DependencySet)
              raise ArgumentError, "must be a DependencySet"
            end
            other.dependencies.each { |dep| self << dep }
            self
          end
        end
      end
    end
  end
end
