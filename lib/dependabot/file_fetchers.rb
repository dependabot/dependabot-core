# frozen_string_literal: true

require "dependabot/file_fetchers/ruby/bundler"

module Dependabot
  module FileFetchers
    @file_fetchers = {
      "bundler" => FileFetchers::Ruby::Bundler
    }

    def self.for_package_manager(package_manager)
      file_fetcher = @file_fetchers[package_manager]
      return file_fetcher if file_fetcher

      raise "Unsupported package_manager #{package_manager}"
    end

    def self.register(package_manager, file_fetcher)
      @file_fetchers[package_manager] = file_fetcher
    end
  end
end
