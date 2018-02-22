# frozen_string_literal: true

require "octokit"
require "gpgme"
require "tmpdir"

module Dependabot
  class PullRequestUpdater
    attr_reader :watched_repo, :files, :base_commit, :github_client,
                :pull_request_number, :author_details, :signature_key

    def initialize(repo:, base_commit:, files:, github_client:,
                   pull_request_number:, author_details: nil,
                   signature_key: nil)
      @watched_repo = repo
      @base_commit = base_commit
      @files = files
      @github_client = github_client
      @pull_request_number = pull_request_number
      @author_details = author_details
      @signature_key = signature_key
    end

    def update
      return unless branch_exists?

      commit = create_commit
      update_branch(commit)
    end

    private

    def pull_request
      @pull_request ||=
        github_client.pull_request(watched_repo, pull_request_number)
    end

    def branch_exists?
      github_client.branch(watched_repo, pull_request.head.ref)
    rescue Octokit::NotFound
      false
    end

    def create_commit
      tree = create_tree

      options = author_details&.any? ? { author: author_details } : {}

      if options[:author]&.any? && signature_key
        timestamp = Time.now.utc
        options[:signature] = commit_signature(tree, timestamp)
        options[:author][:date] = timestamp.iso8601
      end

      github_client.create_commit(
        watched_repo,
        commit_message,
        tree.sha,
        base_commit,
        options
      )
    end

    def create_tree
      file_trees = files.map do |file|
        if file.type == "file"
          {
            path: file.path.sub(%r{^/}, ""),
            mode: "100644",
            type: "blob",
            content: file.content
          }
        elsif file.type == "submodule"
          {
            path: file.path.sub(%r{^/}, ""),
            mode: "160000",
            type: "commit",
            sha: file.content
          }
        else
          raise "Unknown file type #{file.type}"
        end
      end

      github_client.create_tree(
        watched_repo,
        file_trees,
        base_tree: base_commit
      )
    end

    def update_branch(commit)
      github_client.update_ref(
        watched_repo,
        "heads/" + pull_request.head.ref,
        commit.sha,
        true
      )
    rescue Octokit::UnprocessableEntity => error
      # Return quietly if the branch has been deleted
      return nil if error.message.match?(/Reference does not exist/i)

      # Return quietly if the branch has been merged
      return nil if error.message.match?(/Reference cannot be updated/i)
      raise
    end

    def commit_message
      github_client.git_commit(watched_repo, pull_request.head.sha).message
    end

    def commit_signature(tree, timestamp)
      time_str = timestamp.strftime("%s %z")
      name = author_details[:name]
      email = author_details[:email]
      commit_object = [
        "tree #{tree.sha}",
        "parent #{base_commit}",
        "author #{name} <#{email}> #{time_str}",
        "committer #{name} <#{email}> #{time_str}",
        "",
        commit_message
      ]
      data = commit_object.join("\n")

      Dir.mktmpdir do |dir|
        GPGME::Engine.home_dir = dir
        GPGME::Key.import(signature_key)

        crypto = GPGME::Crypto.new(armor: true)
        opts = { mode: GPGME::SIG_MODE_DETACH, signer: email }
        return crypto.sign(data, opts)
      end
    end
  end
end
