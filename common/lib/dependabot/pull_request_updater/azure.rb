# typed: strict
# frozen_string_literal: true

require "securerandom"
require "sorbet-runtime"

require "dependabot/clients/azure"

module Dependabot
  class PullRequestUpdater
    class Azure
      extend T::Sig

      class PullRequestUpdateFailed < Dependabot::DependabotError; end

      OBJECT_ID_FOR_BRANCH_DELETE = "0000000000000000000000000000000000000000"

      sig { returns(Dependabot::Source) }
      attr_reader :source

      sig { returns(T::Array[Dependabot::DependencyFile]) }
      attr_reader :files

      sig { returns(String) }
      attr_reader :base_commit

      sig { returns(String) }
      attr_reader :old_commit

      sig { returns(T::Array[Dependabot::Credential]) }
      attr_reader :credentials

      sig { returns(Integer) }
      attr_reader :pull_request_number

      sig { returns(T.nilable(T::Hash[Symbol, String])) }
      attr_reader :author_details

      sig do
        params(
          source: Dependabot::Source,
          files: T::Array[Dependabot::DependencyFile],
          base_commit: String,
          old_commit: String,
          credentials: T::Array[Dependabot::Credential],
          pull_request_number: Integer,
          author_details: T.nilable(T::Hash[Symbol, String])
        )
          .void
      end
      def initialize(source:, files:, base_commit:, old_commit:,
                     credentials:, pull_request_number:, author_details: nil)
        @source = source
        @files = files
        @base_commit = base_commit
        @old_commit = old_commit
        @credentials = credentials
        @pull_request_number = pull_request_number
        @author_details = author_details
      end

      sig { returns(NilClass) }
      def update
        return unless pull_request_exists? && source_branch_exists?

        update_source_branch
      end

      private

      sig { returns(Dependabot::Clients::Azure) }
      def azure_client_for_source
        @azure_client_for_source ||=
          T.let(
            Dependabot::Clients::Azure.for_source(
              source: source,
              credentials: credentials
            ),
            T.nilable(Dependabot::Clients::Azure)
          )
      end

      sig { returns(T::Boolean) }
      def pull_request_exists?
        pull_request
        true
      rescue Dependabot::Clients::Azure::NotFound
        false
      end

      sig { returns(T::Boolean) }
      def source_branch_exists?
        azure_client_for_source.branch(source_branch_name)
        true
      rescue Dependabot::Clients::Azure::NotFound
        false
      end

      # Currently the PR diff in ADO shows difference in commits instead of actual diff in files.
      # This workaround puts the target branch commit history on the source branch along with the file changes.
      sig { returns(NilClass) }
      def update_source_branch
        # 1) Push the file changes to a newly created temporary branch (from base commit)
        new_commit = create_temp_branch
        # 2) Update PR source branch to point to the temp branch head commit.
        response = update_branch(source_branch_name, old_source_branch_commit, new_commit)
        # 3) Delete temp branch
        update_branch(temp_branch_name, new_commit, OBJECT_ID_FOR_BRANCH_DELETE)

        raise PullRequestUpdateFailed, response.fetch("customMessage", nil) unless response.fetch("success", false)
      end

      sig { returns(T.nilable(T::Hash[String, T.untyped])) }
      def pull_request
        @pull_request ||=
          T.let(
            azure_client_for_source.pull_request(pull_request_number.to_s),
            T.nilable(T::Hash[String, T.untyped])
          )
      end

      sig { returns(String) }
      def source_branch_name
        @source_branch_name ||= T.let(
          pull_request&.fetch("sourceRefName")&.gsub("refs/heads/", ""),
          T.nilable(String)
        )
      end

      sig { returns(String) }
      def create_temp_branch
        author = author_details&.slice(:name, :email, :date)
        author = nil unless author&.any?

        response = azure_client_for_source.create_commit(
          temp_branch_name,
          base_commit,
          commit_message,
          files,
          author
        )

        JSON.parse(response.body).fetch("refUpdates").first.fetch("newObjectId")
      end

      sig { returns(String) }
      def temp_branch_name
        @temp_branch_name ||=
          T.let(
            "#{source_branch_name}-temp-#{SecureRandom.uuid[0..6]}",
            T.nilable(String)
          )
      end

      sig { params(branch_name: String, old_commit: String, new_commit: String).returns(T::Hash[String, T.untyped]) }
      def update_branch(branch_name, old_commit, new_commit)
        azure_client_for_source.update_ref(
          branch_name,
          old_commit,
          new_commit
        )
      end

      # For updating source branch, we require the latest commit for the source branch.
      sig { returns(T::Hash[String, T.untyped]) }
      def commit_being_updated
        @commit_being_updated ||=
          T.let(
            T.must(azure_client_for_source.commits(source_branch_name).first),
            T.nilable(T::Hash[String, T.untyped])
          )
      end

      sig { returns(String) }
      def old_source_branch_commit
        commit_being_updated.fetch("commitId")
      end

      sig { returns(String) }
      def commit_message
        commit_being_updated.fetch("comment")
      end
    end
  end
end
