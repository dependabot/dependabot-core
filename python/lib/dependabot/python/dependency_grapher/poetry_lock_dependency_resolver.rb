# typed: strict
# frozen_string_literal: true

require "sorbet-runtime"
require "toml-rb"

require "dependabot/dependency"
require "dependabot/dependency_file"
require "dependabot/errors"
require "dependabot/file_parsers/base/dependency_set"
require "dependabot/python/name_normaliser"

module Dependabot
  module Python
    class DependencyGrapher < Dependabot::DependencyGraphers::Base
      # Parses poetry.lock directly (independent of the shared file parser's `[tool.poetry]` gating) so the
      # grapher can report parent/child relationships and backfill any package the parser didn't include.
      #
      # The shared file parser only merges poetry.lock's full package set into its dependency set when
      # `[tool.poetry]` is present (see PyprojectDocument#poetry?). The grapher detects Poetry purely from
      # poetry.lock's presence on disk, so a PEP 621-only Poetry 2.0 manifest is correctly graphed as Poetry
      # but would otherwise have every transitive package silently dropped.
      class PoetryLockDependencyResolver
        extend T::Sig

        # A directory/git/url sourced package has no resolvable PyPI release, so it can't be represented as
        # a normal purl-addressed graph node. Mirrors PyprojectFilesParser#lockfile_dependencies.
        UNRESOLVABLE_SOURCE_TYPES = %w(directory git url).freeze

        sig { params(poetry_lock: Dependabot::DependencyFile).void }
        def initialize(poetry_lock)
          @poetry_lock = poetry_lock
        end

        # A map of normalised package name to the normalised names of its direct dependencies.
        sig { returns(T::Hash[String, T::Array[String]]) }
        def relationships
          packages.each_with_object({}) do |pkg, rels|
            deps = pkg["dependencies"]
            deps = {} unless deps.is_a?(Hash)

            rels[normalised_name(pkg)] = deps.keys.map { |name| NameNormaliser.normalise(name) }
          end
        end

        # Synthetic Dependency objects for every resolvable poetry.lock package, as a DependencySet so that
        # packages recorded multiple times (e.g. once per platform marker) have their metadata merged rather
        # than only the first-seen entry's groups deciding production status.
        sig { returns(Dependabot::FileParsers::Base::DependencySet) }
        def dependency_set
          dependencies = Dependabot::FileParsers::Base::DependencySet.new

          packages.each do |pkg|
            next if UNRESOLVABLE_SOURCE_TYPES.include?(source_type(pkg))

            name = normalised_name(pkg)
            dependencies << dependency_for(pkg, name)
          end

          dependencies
        end

        private

        sig { params(pkg: T::Hash[String, Object]).returns(String) }
        def normalised_name(pkg)
          NameNormaliser.normalise(T.cast(pkg["name"], String))
        end

        # Poetry 2.0 lock files record each package's dependency groups directly (e.g. `groups = ["main"]`),
        # so we can tell production from dev packages without running `poetry show`, which the grapher
        # otherwise avoids for lockfile-only (non-ephemeral) projects.
        sig { params(pkg: T::Hash[String, Object], name: String).returns(Dependabot::Dependency) }
        def dependency_for(pkg, name)
          groups = pkg["groups"]
          production = !groups.is_a?(Array) || groups.include?("main")

          Dependabot::Dependency.new(
            name: name,
            version: T.cast(pkg["version"], T.nilable(String)),
            requirements: [],
            package_manager: "pip",
            subdependency_metadata: [{ production: production }]
          )
        end

        sig { params(pkg: T::Hash[String, Object]).returns(T.nilable(String)) }
        def source_type(pkg)
          source = pkg["source"]
          return nil unless source.is_a?(Hash)

          type = source["type"]
          type.is_a?(String) ? type : nil
        end

        sig { returns(T::Array[T::Hash[String, Object]]) }
        def packages
          @packages ||= T.let(
            TomlRB.parse(T.must(poetry_lock.content)).fetch("package", []).grep(Hash).select do |pkg|
              pkg["name"].is_a?(String)
            end,
            T.nilable(T::Array[T::Hash[String, Object]])
          )
        rescue TomlRB::ParseError, TomlRB::ValueOverwriteError
          raise Dependabot::DependencyFileNotParseable, poetry_lock.name
        end

        sig { returns(Dependabot::DependencyFile) }
        attr_reader :poetry_lock
      end
    end
  end
end
