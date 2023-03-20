# frozen_string_literal: true

module Dependabot
  module Python
    class AuthedUrlBuilder
      def self.authed_url(credential:)
        token = credential.fetch("token", nil)
        url = credential.fetch("index-url")
        return url unless token

        basic_auth_details =
          if token.ascii_only? && token.include?(":") then token
          elsif Base64.decode64(token).ascii_only? &&
                Base64.decode64(token).include?(":")
            Base64.decode64(token)
          else
            token
          end

        if basic_auth_details.include?(":")
          username, _, password = basic_auth_details.partition(":")
          basic_auth_details = "#{CGI.escape(username)}:#{CGI.escape(password)}"
        end

        url.sub("://", "://#{basic_auth_details}@")
      end
    end
  end
end
