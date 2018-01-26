# frozen_string_literal: true

require "dependabot/update_checkers/php/composer/version"

module Dependabot
  module UpdateCheckers
    module Php
      class Composer
        class Requirement < Gem::Requirement
          def self.parse(obj)
            new_obj = obj.gsub(/@\w+/, "").gsub(/[a-z0-9\-_\.]*\sas\s+/i, "")
            super(new_obj)
          end
        end
      end
    end
  end
end
