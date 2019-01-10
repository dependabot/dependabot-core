# frozen_string_literal: true

require "dependabot/metadata_finders/ruby/bundler"
require "dependabot/metadata_finders/java_script/npm_and_yarn"
require "dependabot/metadata_finders/go/dep"

module Dependabot
  module MetadataFinders
    @metadata_finders = {
      "bundler" => MetadataFinders::Ruby::Bundler,
      "npm_and_yarn" => MetadataFinders::JavaScript::NpmAndYarn,
      "dep" => MetadataFinders::Go::Dep
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
