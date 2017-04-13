# frozen_string_literal: true
require "octokit"

module Bump
  module Github
    def self.client
      @client ||= Octokit::Client.new(access_token: Prius.get(:bump_github_token))
    end
  end
end
