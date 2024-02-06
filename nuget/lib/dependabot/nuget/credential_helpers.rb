# typed: true
# frozen_string_literal: true

module Dependabot
  module Nuget
    module CredentialHelpers
      def self.get_token_from_credentials(credentials)
        token = credentials["token"]
        username = credentials["username"]
        password = credentials["password"]

        return token if token
        return "#{username}:#{password}" if username && password

        nil
      end
    end
  end
end
