# frozen_string_literal: true

module Dependabot
  class PullRequestCreator
    module Labelers
      class PackageManagerLabels
        attr_reader :language, :colour

        @labels = {}

        def initialize(language, colour)
          @language = language
          @colour = colour
        end

        class << self
          def details(package_manager)
            label_details = @labels[package_manager]
            return label_details if label_details

            raise "Unsupported package_manager #{package_manager}"
          end

          def register_label(package_manager, details)
            @labels[package_manager] = new(details[:name], details[:colour])
          end
        end
      end
    end
  end
end
