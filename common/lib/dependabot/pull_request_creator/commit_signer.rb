# typed: strict
# frozen_string_literal: true

require "time"
require "tmpdir"
require "sorbet-runtime"
require "dependabot/pull_request_creator"

module Dependabot
  class PullRequestCreator
    class CommitSigner
      extend T::Sig

      sig { returns(T::Hash[Symbol, String]) }
      attr_reader :author_details

      sig { returns(String) }
      attr_reader :commit_message

      sig { returns(String) }
      attr_reader :tree_sha

      sig { returns(String) }
      attr_reader :parent_sha

      sig { returns(String) }
      attr_reader :signature_key

      sig do
        params(
          author_details: T::Hash[Symbol, String],
          commit_message: String,
          tree_sha: String,
          parent_sha: String,
          signature_key: String
        ).void
      end
      def initialize(author_details:, commit_message:, tree_sha:, parent_sha:,
                     signature_key:)
        @author_details = author_details
        @commit_message = commit_message
        @tree_sha = tree_sha
        @parent_sha = parent_sha
        @signature_key = signature_key
      end

      sig { returns(String) }
      def signature
        begin
          require "gpgme"
        rescue LoadError
          raise LoadError, "Please add `gpgme` to your Gemfile or gemspec " \
                           "enable commit signatures"
        end

        email = author_details[:email]

        dir = Dir.mktmpdir

        GPGME::Engine.home_dir = dir
        GPGME::Key.import(signature_key)

        crypto = GPGME::Crypto.new(armor: true)
        opts = { mode: GPGME::SIG_MODE_DETACH, signer: email }
        crypto.sign(commit_object, opts).to_s
      rescue Errno::ENOTEMPTY
        FileUtils.remove_entry(T.must(dir), true)
        # This appears to be a Ruby bug which occurs very rarely
        raise if @retrying

        @retrying = T.let(true, T.nilable(T::Boolean))
        retry
      ensure
        FileUtils.remove_entry(T.must(dir), true)
      end

      private

      sig { returns(String) }
      def commit_object
        time_str = Time.parse(T.must(author_details[:date])).strftime("%s %z")
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
