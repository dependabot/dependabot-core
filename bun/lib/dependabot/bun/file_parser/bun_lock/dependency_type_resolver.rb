# typed: strict
# frozen_string_literal: true

require "sorbet-runtime"
require "dependabot/bun/file_parser/bun_lock"

module Dependabot
  module Bun
    class FileParser < Dependabot::FileParsers::Base
      class BunLock
        # Works out whether each bun.lock package is a production or a development
        # dependency. Unlike package-lock.json, bun.lock has no "dev" flag, so this
        # walks the graph from every workspace root instead.
        #
        # A package is production if any path to it starts with a dependencies,
        # optionalDependencies or peerDependencies entry on a workspace. It is
        # development only if every path to it starts with a devDependencies entry.
        class DependencyTypeResolver
          extend T::Sig

          # A parent packages key (nil for a workspace root) and the name of a package it pulls in.
          Edge = T.type_alias { [T.nilable(String), String] }

          SCOPE_SEGMENT = %r{\A@[^/]+\z}

          sig { params(workspaces: T::Array[Workspace], records: T::Hash[String, Record]).void }
          def initialize(workspaces:, records:)
            @workspaces = workspaces
            @records = records
            @production_by_key = T.let(nil, T.nilable(T::Hash[String, T::Boolean]))
          end

          # Maps each reachable packages key to true (production) or false (development).
          # Keys that no workspace reaches are left out.
          sig { returns(T::Hash[String, T::Boolean]) }
          def production_by_key
            @production_by_key ||= begin
              result = T.let({}, T::Hash[String, T::Boolean])
              # Walk production edges first, so a package on both kinds of path stays production.
              walk(root_edges(production: true), result, production: true)
              walk(root_edges(production: false), result, production: false)
              result
            end
          end

          private

          sig { params(production: T::Boolean).returns(T::Array[Edge]) }
          def root_edges(production:)
            @workspaces.flat_map do |workspace|
              names = production ? workspace.production_names : workspace.development_names
              names.map { |name| [workspace.key_prefix, name] }
            end
          end

          sig { params(queue: T::Array[Edge], result: T::Hash[String, T::Boolean], production: T::Boolean).void }
          def walk(queue, result, production:)
            index = 0
            while index < queue.length
              parent_key, child_name = T.must(queue[index])
              index += 1

              key = resolve_key(parent_key, child_name)
              next if key.nil? || result.key?(key)

              result[key] = production
              T.must(@records[key]).edge_names.each { |name| queue << [key, name] }
            end
          end

          # Bun keys a nested copy of a package by the packages it sits under, such as
          # "debug/ms" or "app/is-number". Look under the closest parent first, then
          # move up one level at a time until reaching the hoisted top-level key.
          sig { params(parent_key: T.nilable(String), child_name: String).returns(T.nilable(String)) }
          def resolve_key(parent_key, child_name)
            segments = key_segments(parent_key)
            until segments.empty?
              candidate = [*segments, child_name].join("/")
              return candidate if @records.key?(candidate)

              segments.pop
            end

            @records.key?(child_name) ? child_name : nil
          end

          # Splits a packages key into package names, keeping scoped names such as "@types/node" whole.
          sig { params(key: T.nilable(String)).returns(T::Array[String]) }
          def key_segments(key)
            return [] if key.nil? || key.empty?

            key.split("/").each_with_object(T.let([], T::Array[String])) do |part, segments|
              last = segments.last
              if last&.match?(SCOPE_SEGMENT)
                segments[-1] = "#{last}/#{part}"
              else
                segments << part
              end
            end
          end
        end
      end
    end
  end
end
