# frozen_string_literal: true

require "json"
require "dependabot/errors"

module Dependabot
  module NpmAndYarn
    class FileParser
      class JsonLock
        def initialize(dependency_file)
          @dependency_file = dependency_file
        end

        def parse
          JSON.parse(@dependency_file.content)
        rescue JSON::ParserError
          raise Dependabot::DependencyFileNotParseable, @dependency_file.path
        end
      end
    end
  end
end
