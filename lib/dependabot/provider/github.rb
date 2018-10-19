# frozen_string_literal: true

module Dependabot
  module Provider
    class Github
      def url
        "https://github.com/"
      end

      def hostname
        "github.com"
      end

      def api_endpoint
        "https://api.github.com/"
      end
    end
  end
end
