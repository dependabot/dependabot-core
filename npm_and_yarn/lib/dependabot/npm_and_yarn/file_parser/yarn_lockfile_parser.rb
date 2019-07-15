# frozen_string_literal: true

require "dependabot/dependency_file"
require "dependabot/npm_and_yarn/file_parser"

module Dependabot
  module NpmAndYarn
    class FileParser
      class YarnLockfileParser
        def initialize(lockfile:)
          @content = lockfile.content
        end

        # This is *extremely* crude, but saves us from having to shell out
        # to Yarn, which may not be safe
        def parse
          yaml = convert_to_yaml
          lockfile_object = parse_as_yaml(yaml)
          expand_lockfile_requirements(lockfile_object)
        end

        private

        attr_reader :content

        # Transform lockfile to parseable YAML by wrapping requirements in
        # quotes, e.g. ("pkg@1.0.0":) and adding colon to nested
        # properties (version: "1.0.0")
        def convert_to_yaml
          sanitize_requirement = lambda do |line|
            return line unless line.match?(/^[\w"]/)

            "\"#{line.gsub(/\"|:\n$/, '')}\":\n"
          end
          add_missing_colon = ->(l) { l.sub(/(?<=\w|")\s(?=\w|")/, ": ") }

          content.lines.map(&sanitize_requirement).map(&add_missing_colon).join
        end

        def parse_as_yaml(yaml)
          YAML.safe_load(yaml)
        rescue Psych::SyntaxError, Psych::DisallowedClass, Psych::BadAlias
          {}
        end

        # Split all comma separated keys and duplicate the lockfile entry
        # so we get one entry per version requirement, this is needed when
        # one of the requirements specifies a file: requirement, e.g.
        # "pkga@file:./pkg, pkgb@1.0.0 and we want to check this in
        # `details_from_yarn_lock`
        def expand_lockfile_requirements(lockfile_object)
          lockfile_object.to_a.each_with_object({}) do |(names, val), res|
            names.split(", ").each { |name| res[name] = val }
          end
        end
      end
    end
  end
end
