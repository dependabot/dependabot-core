# frozen_string_literal: true

require "time"
require "gpgme"
require "tmpdir"
require "dependabot/pull_request_creator"

module Dependabot
  class PullRequestCreator
    class CommitSigner
      attr_reader :author_details, :commit_message, :tree_sha, :parent_sha,
                  :signature_key

      def initialize(author_details:, commit_message:, tree_sha:, parent_sha:,
                     signature_key:)
        @author_details = author_details
        @commit_message = commit_message
        @tree_sha = tree_sha
        @parent_sha = parent_sha
        @signature_key = signature_key
      end

      def signature
        email = author_details[:email]

        Dir.mktmpdir do |dir|
          GPGME::Engine.home_dir = dir
          GPGME::Key.import(signature_key)

          crypto = GPGME::Crypto.new(armor: true)
          opts = { mode: GPGME::SIG_MODE_DETACH, signer: email }
          crypto.sign(commit_object, opts).to_s
        end
      end

      private

      def commit_object
        time_str = Time.parse(author_details[:date]).strftime("%s %z")
        name = author_details[:name]
        email = author_details[:email]

        [
          "tree #{tree_sha}",
          "parent #{parent_sha}",
          "author #{name} <#{email}> #{time_str}",
          "committer #{name} <#{email}> #{time_str}",
          "",
          commit_message
        ].join("\n")
      end
    end
  end
end
