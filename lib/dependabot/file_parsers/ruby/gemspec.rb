# frozen_string_literal: true
require "dependabot/dependency"
require "dependabot/file_parsers/ruby/bundler"
require "dependabot/file_fetchers/ruby/gemspec"
require "dependabot/shared_helpers"
require "dependabot/errors"

module Dependabot
  module FileParsers
    module Ruby
      class Gemspec < Dependabot::FileParsers::Ruby::Bundler
        private

        def required_files
          Dependabot::FileFetchers::Ruby::Gemspec.required_files
        end
      end
    end
  end
end
