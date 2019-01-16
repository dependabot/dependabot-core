# frozen_string_literal: true

require "dependabot/metadata_finders/ruby/bundler"

module Dependabot
  module MetadataFinders
    @metadata_finders = {
      "bundler" => MetadataFinders::Ruby::Bundler
    }

    def self.for_package_manager(package_manager)
      metadata_finder = @metadata_finders[package_manager]
      return metadata_finder if metadata_finder

      raise "Unsupported package_manager #{package_manager}"
    end

    def self.register(package_manager, metadata_finder)
      @metadata_finders[package_manager] = metadata_finder
    end
  end
end
