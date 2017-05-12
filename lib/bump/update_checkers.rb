# frozen_string_literal: true
require "bump/update_checkers/ruby"
require "bump/update_checkers/python"
require "bump/update_checkers/java_script"
require "bump/update_checkers/cocoa"

module Bump
  module UpdateCheckers
    def self.for_language(language)
      case language
      when "ruby" then UpdateCheckers::Ruby
      when "javascript" then UpdateCheckers::JavaScript
      when "python" then UpdateCheckers::Python
      when "cocoa" then UpdateCheckers::Cocoa
      else raise "Invalid language #{language}"
      end
    end
  end
end
