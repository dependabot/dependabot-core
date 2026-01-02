# typed: strict
# frozen_string_literal: true

require "dependabot/dependency"
require "dependabot/file_parsers"
require "dependabot/file_parsers/base"

module Dependabot
  module Opam
    class FileParser < Dependabot::FileParsers::Base
      # Parser for opam file format
      # Extracts dependencies from depends and depopts fields
      class OpamParser
        extend T::Sig

        sig { params(content: String).returns(T::Hash[String, T.nilable(String)]) }
        def self.extract_depends(content)
          extract_dependency_field(content, "depends")
        end

        sig { params(content: String).returns(T::Hash[String, T.nilable(String)]) }
        def self.extract_depopts(content)
          extract_dependency_field(content, "depopts")
        end

        sig { params(content: String, field_name: String).returns(T::Hash[String, T.nilable(String)]) }
        def self.extract_dependency_field(content, field_name)
          dependencies = {}

          # Match field: [ ... ] pattern
          # The field can span multiple lines

          field_regex = /#{field_name}:\s*\[(.*?)\]/m
          match = content.match(field_regex)

          return dependencies unless match

          deps_content = T.must(match[1])

          # Parse each dependency entry
          # Format: "package-name" { version-constraints }
          # or just: "package-name"
          dep_regex = /"([^"]+)"\s*(?:\{([^}]+)\})?/

          deps_content.scan(dep_regex) do |package_name, constraints|
            # Clean up constraints
            constraints = constraints&.strip

            # Skip comment lines and filter conditions
            next if package_name.start_with?("#")
            next if constraints&.include?("with-test")
            next if constraints&.include?("with-doc")

            # Extract version requirements
            # Remove filters and keep only version constraints
            version_constraint = extract_version_constraint(constraints)

            dependencies[package_name] = version_constraint
          end

          dependencies
        end

        sig { params(constraints: T.nilable(String)).returns(T.nilable(String)) }
        def self.extract_version_constraint(constraints)
          return nil if constraints.nil? || constraints.empty?

          # Remove common filters
          constraints = constraints.gsub(/\s*\{[^}]*\}/, "")
          constraints = constraints.strip

          # Remove boolean operators that are not part of version constraints
          # Keep operators like >=, <=, =, <, >, !=
          # Parse constraints like: >= "4.08" & < "5.0"
          version_parts = []

          # Match version constraints
          constraint_regex = /([><=!]+)\s*"([^"]+)"/
          constraints.scan(constraint_regex) do |operator, version|
            version_parts << "#{operator} #{version}"
          end

          return nil if version_parts.empty?

          version_parts.join(" & ")
        end
      end
    end
  end
end
