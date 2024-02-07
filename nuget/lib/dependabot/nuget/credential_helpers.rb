# typed: true
# frozen_string_literal: true

module Dependabot
  module Nuget
    module CredentialHelpers
      def self.get_token_from_credential(credential)
        token = credential["token"]
        username = credential["username"]
        password = credential["password"]

        return token if token
        return "#{username}:#{password}" if username && password

        nil
      end
    end
  end
end
