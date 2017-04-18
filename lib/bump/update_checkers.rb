# frozen_string_literal: true
require "bump/update_checkers/ruby"
require "bump/update_checkers/python"
require "bump/update_checkers/node"

module Bump
  module UpdateCheckers
    def self.for_language(language)
      case language
      when "ruby" then UpdateCheckers::Ruby
      when "node" then UpdateCheckers::Node
      when "python" then UpdateCheckers::Python
      else raise "Invalid language #{language}"
      end
    end
  end
end
