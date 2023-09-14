# typed: strong
# frozen_string_literal: true

require "sorbet-runtime"
require "dependabot/update_checkers/base"

module Dependabot
  module UpdateCheckers
    extend T::Sig

    @update_checkers = T.let({}, T::Hash[String, T.class_of(Dependabot::UpdateCheckers::Base)])

    sig { params(package_manager: String).returns(T.class_of(Dependabot::UpdateCheckers::Base)) }
    def self.for_package_manager(package_manager)
      update_checker = @update_checkers[package_manager]
      return update_checker if update_checker

      raise "Unsupported package_manager #{package_manager}"
    end

    sig { params(package_manager: String, update_checker: T.class_of(Dependabot::UpdateCheckers::Base)).void }
    def self.register(package_manager, update_checker)
      @update_checkers[package_manager] = update_checker
    end
  end
end
