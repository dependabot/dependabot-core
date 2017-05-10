# frozen_string_literal: true
require "bump/dependency_file_fetchers/base"

module Bump
  module DependencyFileFetchers
    class Ruby < Base
      def required_files
        %w(Gemfile Gemfile.lock)
      end
    end
  end
end
