# typed: strong
# frozen_string_literal: true

require "sorbet-runtime"
require "dependabot/metadata_finders/base"

module Dependabot
  module MetadataFinders
    extend T::Sig

    @metadata_finders = T.let({}, T::Hash[String, T.class_of(Dependabot::MetadataFinders::Base)])

    sig { params(package_manager: String).returns(T.class_of(Dependabot::MetadataFinders::Base)) }
    def self.for_package_manager(package_manager)
      metadata_finder = @metadata_finders[package_manager]
      return metadata_finder if metadata_finder

      raise "Unsupported package_manager #{package_manager}"
    end

    sig { params(package_manager: String, metadata_finder: T.class_of(Dependabot::MetadataFinders::Base)).void }
    def self.register(package_manager, metadata_finder)
      @metadata_finders[package_manager] = metadata_finder
    end
  end
end
