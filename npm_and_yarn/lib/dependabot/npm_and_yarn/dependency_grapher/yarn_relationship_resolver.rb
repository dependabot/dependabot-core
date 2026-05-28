# typed: strict
# frozen_string_literal: true

require "sorbet-runtime"
require "dependabot/npm_and_yarn/file_parser/yarn_lock"

module Dependabot
  module NpmAndYarn
    class DependencyGrapher < Dependabot::DependencyGraphers::Base
      class YarnRelationshipResolver
        extend T::Sig

        sig { params(lockfile: Dependabot::DependencyFile).void }
        def initialize(lockfile)
          @lockfile = lockfile
        end

        sig { returns(T::Hash[String, T::Array[String]]) }
        def relationships
          parsed = FileParser::YarnLock.new(@lockfile).parsed

          parsed.each_with_object({}) do |(req, details), rels|
            next unless details.is_a?(Hash)

            version = details["version"]
            parent_name = T.must(req.split(/(?<=\w)\@/).first)
            children = details.fetch("dependencies", {})

            next if children.nil? || children.empty?

            key = "#{parent_name}@#{version}"
            resolved_children = resolve_children(children, parsed)

            rels[key] ||= []
            rels[key].concat(resolved_children).uniq!
          end
        end

        private

        sig { params(children: T::Hash[String, String], parsed: T::Hash[String, T.untyped]).returns(T::Array[String]) }
        def resolve_children(children, parsed)
          children.filter_map do |child_name, child_req|
            version = resolve_child_version(child_name, child_req, parsed)
            "#{child_name}@#{version}" if version
          end
        end

        sig { params(child_name: String, child_req: String, parsed: T::Hash[String, T.untyped]).returns(T.nilable(String)) }
        def resolve_child_version(child_name, child_req, parsed)
          # Try exact key first
          child_entry = parsed["#{child_name}@#{child_req}"]
          return child_entry["version"] if child_entry && child_entry["version"]

          # Yarn groups multiple requirements into single keys like "foo@^1.0.0, foo@^1.2.0"
          target_req = "#{child_name}@#{child_req}"
          grouped_match = parsed.find { |k, _| k.split(", ").include?(target_req) }
          return grouped_match.last["version"] if grouped_match && grouped_match.last["version"]

          # Fallback: find by name only if there's exactly one candidate
          candidates = parsed.select { |k, _| k.split(/(?<=\w)\@/).first == child_name }
          candidate = candidates.first
          candidate.last["version"] if candidates.size == 1 && candidate
        end
      end
    end
  end
end
