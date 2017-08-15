# frozen_string_literal: true
require "dependabot/file_updaters/ruby/bundler"
require "dependabot/file_fetchers/ruby/gemspec"

module Dependabot
  module FileUpdaters
    module Ruby
      class Gemspec < Dependabot::FileUpdaters::Ruby::Bundler
        private

        def required_files
          Dependabot::FileFetchers::Ruby::Gemspec.required_files
        end
      end
    end
  end
end
