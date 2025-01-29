# typed: strict
# frozen_string_literal: true

require "sorbet-runtime"

module Dependabot
  module Python
    module NameNormaliser
      extend T::Sig

      sig { params(name: String).returns(String) }
      def self.normalise(name)
        extras_regex = /\[.+\]/
        name.downcase.gsub(/[-_.]+/, "-").gsub(extras_regex, "")
      end

      sig { params(name: String, extras: T::Array[String]).returns(String) }
      def self.normalise_including_extras(name, extras)
        normalised_name = normalise(name)
        return normalised_name if extras.empty?

        normalised_name + "[" + extras.join(",") + "]"
      end
    end
  end
end
