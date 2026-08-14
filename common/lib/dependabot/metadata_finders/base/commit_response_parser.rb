# typed: strong
# frozen_string_literal: true

require "dependabot/errors"
require "sorbet-runtime"

module Dependabot
  module MetadataFinders
    class Base
      class CommitResponseParser
        extend T::Sig

        sig { params(source_url: String).void }
        def initialize(source_url:)
          @source_url = source_url
        end

        sig { params(commit: Sawyer::Resource).returns(String) }
        def github_commit_sha(commit)
          sawyer_string(commit, :sha, "commit")
        end

        sig { params(commit: Sawyer::Resource).returns(String) }
        def github_commit_message(commit)
          details = T.cast(commit[:commit], Object)
          raise_bad_response("GitHub", "commit details must be an object") unless details.is_a?(Sawyer::Resource)

          sawyer_string(details, :message, "commit")
        end

        sig { params(resource: Sawyer::Resource, key: Symbol, context: String).returns(String) }
        def sawyer_string(resource, key, context)
          value = T.cast(resource[key], Object)
          return value if value.is_a?(String)

          raise_bad_response("GitHub", "#{context} #{key} must be a string")
        end

        sig { params(resource: Gitlab::ObjectifiedHash, key: String, context: String).returns(String) }
        def gitlab_string(resource, key, context)
          value = T.cast(resource[key], Object)
          return value if value.is_a?(String)

          raise_bad_response("GitLab", "#{context} #{key} must be a string")
        end

        sig { params(object: T::Hash[String, Object], key: String, context: String).returns(String) }
        def object_string(object, key, context)
          value = object[key]
          return value if value.is_a?(String)

          raise_bad_response("Azure", "#{context} #{key} must be a string")
        end

        sig { params(provider: String, message: String).returns(T.noreturn) }
        def raise_bad_response(provider, message)
          raise Dependabot::PrivateSourceBadResponse.new(
            @source_url,
            "Malformed #{provider} commit response: #{message}"
          )
        end
      end
    end
  end
end
