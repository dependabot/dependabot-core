# typed: true
# frozen_string_literal: true

module Dependabot
  module Cargo
    module Helpers
      def self.setup_credentials_in_environment(credentials)
          credentials.each do |cred|
            next if cred["type"] != "cargo_registry"

            # Prepare credentials for Cargo private registries
            ENV["CARGO_REGISTRIES_#{cred['registry'].upcase.tr("-", "_")}_TOKEN"] ||= "Token #{cred["token"]}"
          end
      end
    end
  end
end
