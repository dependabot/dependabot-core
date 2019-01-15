# frozen_string_literal: true

require "dependabot/file_parsers/ruby/bundler"

module Dependabot
  module FileParsers
    @file_parsers = {
      "bundler" => FileParsers::Ruby::Bundler
    }

    def self.for_package_manager(package_manager)
      file_parser = @file_parsers[package_manager]
      return file_parser if file_parser

      raise "Unsupported package_manager #{package_manager}"
    end

    def self.register(package_manager, file_parser)
      @file_parsers[package_manager] = file_parser
    end
  end
end
