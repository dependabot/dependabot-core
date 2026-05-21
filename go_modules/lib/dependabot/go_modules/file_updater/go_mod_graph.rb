# typed: strict
# frozen_string_literal: true

require "sorbet-runtime"
require "open3"

require "dependabot/go_modules/file_updater"

module Dependabot
  module GoModules
    class FileUpdater < Dependabot::FileUpdaters::Base
      # Captures and parses the output of `go mod graph` to provide
      # a structured view of the module dependency graph.
      # Can be used to detect which modules changed between two states.
      class GoModGraph
        extend T::Sig

        sig { returns(T::Set[String]) }
        attr_reader :modules

        sig { params(modules: T::Set[String]).void }
        def initialize(modules: Set.new)
          @modules = modules
        end

        # Captures the current module graph by running `go mod graph`.
        # Returns a new GoModGraph instance, or an empty one if the
        # command fails (non-fatal — callers can proceed without it).
        sig { returns(GoModGraph) }
        def self.capture
          stdout, _, status = Open3.capture3("go mod graph")
          return new unless status.success?

          new(modules: parse_graph(stdout))
        end

        # Returns the set of module paths (without versions) that
        # differ between this graph and another — modules that were
        # added, removed, or changed version.
        sig { params(other: GoModGraph).returns(T::Set[String]) }
        def changed_modules(other)
          changed = T.let(Set.new, T::Set[String])

          # Group by module path, compare versions
          before_by_path = group_by_path(modules)
          after_by_path = group_by_path(other.modules)

          all_paths = before_by_path.keys.to_set | after_by_path.keys.to_set
          all_paths.each do |path|
            before_versions = before_by_path.fetch(path, Set.new)
            after_versions = after_by_path.fetch(path, Set.new)
            changed.add(path) if before_versions != after_versions
          end

          changed
        end

        # Returns true if the graph has no modules (e.g. capture failed).
        sig { returns(T::Boolean) }
        def empty?
          modules.empty?
        end

        class << self
          extend T::Sig

          private

          # Parses `go mod graph` output into a set of "module@version" entries.
          # Each line is "parent@version child@version".
          sig { params(output: String).returns(T::Set[String]) }
          def parse_graph(output)
            result = T.let(Set.new, T::Set[String])

            output.each_line do |line|
              line.strip.split(/\s+/).each do |entry|
                # Only include versioned entries (module@version), skip
                # the root module which has no @version suffix.
                result.add(entry) if entry.include?("@")
              end
            end

            result
          end
        end

        private

        # Groups "module@version" entries by module path.
        # Returns { "module/path" => Set["v1.0.0", "v2.0.0"] }
        sig { params(entries: T::Set[String]).returns(T::Hash[String, T::Set[String]]) }
        def group_by_path(entries)
          result = T.let(Hash.new { |h, k| h[k] = Set.new }, T::Hash[String, T::Set[String]])

          entries.each do |entry|
            at_index = entry.rindex("@")
            next unless at_index

            path = entry[0...at_index]
            version = entry[(at_index + 1)..]
            next unless path && version && !path.empty?

            T.must(result[path]).add(version)
          end

          result
        end
      end
    end
  end
end
