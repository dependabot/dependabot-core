# frozen_string_literal: true

require "toml-rb"
require "dependabot/python/file_parser"
require "dependabot/python/name_normaliser"

module Dependabot
  module Python
    class FileParser
      class PoetrySubdependencyTypeParser
        def initialize(lockfile:)
          @lockfile = lockfile
        end

        def subdep_type(dep)
          category =
            TomlRB.parse(lockfile.content).fetch("package", []).
            find { |dets| normalise(dets.fetch("name")) == dep.name }.
            fetch("category")

          category == "dev" ? "dev-dependencies" : "dependencies"
        end

        private

        attr_reader :lockfile

        def normalise(name)
          NameNormaliser.normalise(name)
        end
      end
    end
  end
end
