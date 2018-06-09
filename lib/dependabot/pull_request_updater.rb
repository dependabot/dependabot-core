# frozen_string_literal: true

require "dependabot/pull_request_updater/github"

module Dependabot
  class PullRequestUpdater
    attr_reader :source, :files, :base_commit, :credentials,
                :pull_request_number, :author_details, :signature_key

    def initialize(source:, base_commit:, files:, credentials:,
                   pull_request_number:, author_details: nil,
                   signature_key: nil)
      @source              = source
      @base_commit         = base_commit
      @files               = files
      @credentials         = credentials
      @pull_request_number = pull_request_number
      @author_details      = author_details
      @signature_key       = signature_key
    end

    def update
      Github.new(
        source: source,
        base_commit: base_commit,
        files: files,
        credentials: credentials,
        pull_request_number: pull_request_number,
        author_details: author_details,
        signature_key: signature_key
      ).update
    end
  end
end
