# typed: strong
# frozen_string_literal: true

require "sorbet-runtime"
require "dependabot/file_fetchers/base"

module Dependabot
  module FileFetchers
    extend T::Sig

    @file_fetchers = T.let({}, T::Hash[String, T.class_of(Dependabot::FileFetchers::Base)])

    sig { params(package_manager: String).returns(T.class_of(Dependabot::FileFetchers::Base)) }
    def self.for_package_manager(package_manager)
      file_fetcher = @file_fetchers[package_manager]
      return file_fetcher if file_fetcher

      raise "Unsupported package_manager #{package_manager}"
    end

    sig { params(package_manager: String, file_fetcher: T.class_of(Dependabot::FileFetchers::Base)).void }
    def self.register(package_manager, file_fetcher)
      @file_fetchers[package_manager] = file_fetcher
    end
  end
end
