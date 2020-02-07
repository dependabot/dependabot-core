# frozen_string_literal: true

module Dependabot
  module Python
    module NameNormaliser
      def self.normalise(name)
        extras_regex = /\[.+\]/
        name.downcase.gsub(/[-_.]+/, "-").gsub(extras_regex, "")
      end

      def self.normalise_including_extras(name, extras)
        normalised_name = normalise(name)
        return normalised_name if extras.empty?

        normalised_name + "[" + extras.join(",") + "]"
      end
    end
  end
end
