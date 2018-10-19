# frozen_string_literal: true

module Dependabot
  module Provider
    class Gitlab
      def url
        "https://gitlab.com/"
      end

      def hostname
        "gitlab.com"
      end

      def api_endpoint
        "https://gitlab.com/api/v4"
      end
    end
  end
end
