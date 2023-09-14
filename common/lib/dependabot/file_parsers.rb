# typed: strong
# frozen_string_literal: true

require "sorbet-runtime"
require "dependabot/file_parsers/base"

module Dependabot
  module FileParsers
    extend T::Sig

    @file_parsers = T.let({}, T::Hash[String, T.class_of(Dependabot::FileParsers::Base)])

    sig { params(package_manager: String).returns(T.class_of(Dependabot::FileParsers::Base)) }
    def self.for_package_manager(package_manager)
      file_parser = @file_parsers[package_manager]
      return file_parser if file_parser

      raise "Unsupported package_manager #{package_manager}"
    end

    sig { params(package_manager: String, file_parser: T.class_of(Dependabot::FileParsers::Base)).void }
    def self.register(package_manager, file_parser)
      @file_parsers[package_manager] = file_parser
    end
  end
end
