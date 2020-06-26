# frozen_string_literal: true

require "dependabot/paket/file_parser"
require "dependabot/update_checkers"
require "dependabot/update_checkers/base"

module Dependabot
  module Paket
    class UpdateChecker < Dependabot::UpdateCheckers::Base

    end
  end
end

Dependabot::UpdateCheckers.register("paket", Dependabot::Paket::UpdateChecker)
