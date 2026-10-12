# typed: strict
# frozen_string_literal: true

require "json"
require "sorbet-runtime"

module Dependabot
  module NpmAndYarn
    class DependencyGrapher < Dependabot::DependencyGraphers::Base
      class NpmRelationshipResolver
        extend T::Sig

        sig { params(lockfile: Dependabot::DependencyFile).void }
        def initialize(lockfile)
          @lockfile = lockfile
        end

        sig { returns(T::Hash[String, T::Array[String]]) }
        def relationships
          parsed = JSON.parse(T.must(@lockfile.content))
          packages = parsed.fetch("packages", {})

          # v3/v2 lockfiles use a flat "packages" section
          return build_v3_relationships(packages) if packages.is_a?(Hash) && !packages.empty?

          # if packages isn't present, attempt a v1 fallback
          build_v1_relationships(parsed)
        end

        private

        sig { params(packages: T::Hash[String, T.untyped]).returns(T::Hash[String, T::Array[String]]) }
        def build_v3_relationships(packages)
          packages.each_with_object({}) do |(path, details), rels|
            next if path.empty? # skip root package entry
            next unless details.is_a?(Hash)

            children = details.fetch("dependencies", {}).keys
            next if children.empty?

            package_name = details["name"] || path.split("node_modules/").last
            version = details["version"]
            next if version.nil? || version.to_s.empty?

            resolved = resolve_v3_children(packages, path, children)
            rels["#{package_name}@#{version}"] = resolved unless resolved.empty?
          end
        end

        sig do
          params(
            packages: T::Hash[String, T.untyped],
            parent_path: String,
            children: T::Array[String]
          ).returns(T::Array[String])
        end
        def resolve_v3_children(packages, parent_path, children)
          children.filter_map do |child_name|
            child_details = resolve_child(packages, parent_path, child_name)
            next unless child_details

            child_version = child_details["version"]
            next if child_version.nil? || child_version.to_s.empty?

            # Use the "name" field for aliased packages (real name vs path alias)
            real_name = child_details["name"] || child_name
            "#{real_name}@#{child_version}"
          end
        end

        # Walks up the node_modules tree to resolve a child dependency,
        # matching Node.js module resolution behavior.
        sig do
          params(
            packages: T::Hash[String, T.untyped],
            parent_path: String,
            child_name: String
          ).returns(T.nilable(T::Hash[String, T.untyped]))
        end
        def resolve_child(packages, parent_path, child_name)
          # First check directly nested under parent
          candidate = "#{parent_path}/node_modules/#{child_name}"
          return packages[candidate] if packages.key?(candidate)

          # Walk up the tree: strip trailing node_modules/pkg segments
          segments = parent_path.split("node_modules/")
          segments.pop # remove the current package segment

          while segments.any?
            candidate = "#{segments.join('node_modules/')}node_modules/#{child_name}"
            return packages[candidate] if packages.key?(candidate)

            segments.pop
          end

          # Top-level fallback
          packages["node_modules/#{child_name}"]
        end

        sig { params(parsed: T::Hash[String, T.untyped]).returns(T::Hash[String, T::Array[String]]) }
        def build_v1_relationships(parsed)
          dependencies = parsed.fetch("dependencies", {})
          return {} unless dependencies.is_a?(Hash)

          dependencies.each_with_object({}) do |(name, details), rels|
            next unless details.is_a?(Hash)

            nested = details.fetch("dependencies", nil)
            next unless nested.is_a?(Hash)

            version = details["version"]
            next if version.nil? || version.to_s.empty?

            children = resolve_v1_children(nested)
            rels["#{name}@#{version}"] = children unless children.empty?
            rels.merge!(build_v1_relationships(details))
          end
        end

        sig { params(nested: T::Hash[String, T.untyped]).returns(T::Array[String]) }
        def resolve_v1_children(nested)
          nested.filter_map do |child_name, child_details|
            next unless child_details.is_a?(Hash)

            child_version = child_details["version"]
            next if child_version.nil? || child_version.to_s.empty?

            "#{child_name}@#{child_version}"
          end
        end
      end
    end
  end
end
