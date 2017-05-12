# frozen_string_literal: true
require "bump/dependency_file_fetchers/base"

module Bump
  module DependencyFileFetchers
    class Cocoa < Base
      def self.required_files
        %w(Podfile Podfile.lock)
      end
    end
  end
end
