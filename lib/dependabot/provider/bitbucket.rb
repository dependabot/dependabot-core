# frozen_string_literal: true

module Dependabot
  module Provider
    class BitBucket
      def url
        "https://bitbucket.org/"
      end

      def hostname
        "bitbucket.org"
      end

      def api_endpoint
        "https://api.bitbucket.org/2.0/"
      end
    end
  end
end
