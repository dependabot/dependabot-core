# frozen_string_literal: true

module Dependabot
  module UpdateCheckers
    module VersionFilters
      def self.filter_vulnerable_versions(versions_array, security_advisories)
        versions_array.reject do |v|
          security_advisories.any? do |a|
            if v.is_a?(Gem::Version)
              a.vulnerable?(v)
            else
              a.vulnerable?(v.fetch(:version))
            end
          end
        end
      end
    end
  end
end
