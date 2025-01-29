# typed: strong
# frozen_string_literal: true

require "sorbet-runtime"
require "dependabot/file_updaters/base"

module Dependabot
  module FileUpdaters
    extend T::Sig

    @file_updaters = T.let({}, T::Hash[String, T.class_of(Dependabot::FileUpdaters::Base)])

    sig { params(package_manager: String).returns(T.class_of(Dependabot::FileUpdaters::Base)) }
    def self.for_package_manager(package_manager)
      file_updater = @file_updaters[package_manager]
      return file_updater if file_updater

      raise "Unsupported package_manager #{package_manager}"
    end

    sig { params(package_manager: String, file_updater: T.class_of(Dependabot::FileUpdaters::Base)).void }
    def self.register(package_manager, file_updater)
      @file_updaters[package_manager] = file_updater
    end
  end
end
