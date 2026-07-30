# typed: strong
# frozen_string_literal: true

require "octokit"
require "sorbet-runtime"

module Dependabot
  module FileFetcherCommandConnectivity
    extend T::Sig
    extend T::Helpers

    abstract!

    private

    sig { abstract.returns(Dependabot::Job) }
    def job; end

    sig { void }
    def connectivity_check
      Dependabot.logger.info("Connectivity check starting")
      github_connectivity_client(job).repository(job.source.repo)
      Dependabot.logger.info("Connectivity check successful")
    rescue StandardError => e
      Dependabot.logger.error("Connectivity check failed: #{e.message}")
    end

    sig { params(job: Dependabot::Job).returns(Octokit::Client) }
    def github_connectivity_client(job)
      Octokit::Client.new(
        {
          api_endpoint: job.source.api_endpoint,
          connection_options: {
            request: {
              open_timeout: 20,
              timeout: 5
            }
          }
        }
      )
    end
  end
end
