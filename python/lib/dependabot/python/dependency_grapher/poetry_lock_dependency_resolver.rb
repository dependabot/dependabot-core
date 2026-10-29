# typed: strict
# frozen_string_literal: true

require "sorbet-runtime"
require "toml-rb"

require "dependabot/dependency"
require "dependabot/dependency_file"
require "dependabot/errors"
require "dependabot/python/name_normaliser"

module Dependabot
  module Python
    class DependencyGrapher < Dependabot::DependencyGraphers::Base
      # Parses poetry.lock directly to report parent/child relationships between packages, which the shared
      # file parser's dependency set doesn't expose.
      class PoetryLockDependencyResolver
        extend T::Sig

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

        private

        sig { params(pkg: T::Hash[String, Object]).returns(String) }
        def normalised_name(pkg)
          NameNormaliser.normalise(T.cast(pkg["name"], String))
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
