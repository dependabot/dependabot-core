# typed: strict
# frozen_string_literal: true

require "yaml"
require "sorbet-runtime"

module Dependabot
  module NpmAndYarn
    class DependencyGrapher < Dependabot::DependencyGraphers::Base
      class PnpmRelationshipResolver
        extend T::Sig

        sig { params(lockfile: Dependabot::DependencyFile).void }
        def initialize(lockfile)
          @lockfile = lockfile
        end

        sig { returns(T::Hash[String, T::Array[String]]) }
        def relationships
          parsed = YAML.safe_load(T.must(@lockfile.content)) || {}

          # v9+ uses "snapshots" for resolved dependency details; v6 uses "packages"
          entries = parsed.fetch("snapshots", nil) || parsed.fetch("packages", {})

          entries.each_with_object({}) do |(key, details), rels|
            next unless details.is_a?(Hash)

            # Keys are "/name@version" (v6) or "name@version" (v9)
            name_version = key.sub(%r{^/}, "")
            children = details.fetch("dependencies", {})

            next if children.nil? || children.empty?

            # Strip any pnpm suffix metadata (e.g., parenthesized peer dep info)
            name_version = name_version.sub(/\(.*\)$/, "")

            # pnpm dependencies are already resolved: {"name": "version"}
            # Strip any peer metadata suffixes like "7.49.0(react@18.2.0)"
            resolved_children = children.filter_map do |child_name, child_version|
              clean_version = child_version.to_s.sub(/\(.*\)$/, "")
              next if clean_version.empty?

              "#{child_name}@#{clean_version}"
            end

            rels[name_version] ||= []
            rels[name_version].concat(resolved_children).uniq!
          end
        end
      end
    end
  end
end
