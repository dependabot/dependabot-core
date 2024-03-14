# typed: strict
# frozen_string_literal: true

require "sorbet-runtime"

require "dependabot/api_client"
require "dependabot/service"

module Dependabot
  module Sorbet
    module Runtime
      class InformationalError < StandardError; end
      extend T::Sig

      sig { void }
      def self.silently_report_errors!
        T::Configuration.call_validation_error_handler = lambda do |_sig, opts|
          error = InformationalError.new(opts[:pretty_message])
          error.set_backtrace(caller.dup)

          api_client =
            Dependabot::ApiClient.new(
              Environment.api_url,
              Environment.job_id,
              Environment.job_token
            )

          Dependabot::Service.new(client: api_client).capture_exception(error: error)
        end
      end
    end
  end
end
