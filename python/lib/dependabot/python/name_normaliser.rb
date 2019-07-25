# frozen_string_literal: true

module Dependabot
  module Python
    module NameNormaliser
      def self.normalise(name)
        name.downcase.gsub(/[-_.]+/, "-")
      end
    end
  end
end
