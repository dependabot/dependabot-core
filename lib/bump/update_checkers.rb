# frozen_string_literal: true
require "bump/update_checkers/ruby"
require "bump/update_checkers/python"
require "bump/update_checkers/java_script"

module Bump
  module UpdateCheckers
    def self.for_language(language)
      case language
      when "ruby" then UpdateCheckers::Ruby
      when "javascript" then UpdateCheckers::JavaScript
      when "python" then UpdateCheckers::Python
      else raise "Invalid language #{language}"
      end
    end
  end
end
