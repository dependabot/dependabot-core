# typed: strong
# frozen_string_literal: true

require "sorbet-runtime"
require "sawyer"
require "time"
require "dependabot/errors"

module Dependabot
  module Nix
    module Package
      class RevisionCandidate < T::ImmutableStruct
        extend T::Sig

        JsonObject = T.type_alias { T::Hash[String, Object] }

        const :revision, String
        const :released_at, T.nilable(Time), default: nil
        const :previous_revision, T.nilable(String), default: nil

        sig { params(value: Object, source: String).returns(RevisionCandidate) }
        def self.from_activity(value, source:)
          invalid!(source, "activity", "an object") unless value.is_a?(Sawyer::Resource)

          previous = T.cast(value[:before], Object)
          new(
            revision: string(T.cast(value[:after], Object), source, "activity.after"),
            released_at: parsed_time(T.cast(value[:timestamp], Object)),
            previous_revision: previous.is_a?(String) ? previous : nil
          )
        end

        sig { params(value: Object, source: String).returns(RevisionCandidate) }
        def self.from_commit(value, source:)
          fields = object(value, source, "commit")
          details = optional_object(fields["commit"], source, "commit details")
          committer = optional_object(details&.[]("committer"), source, "commit.committer")
          new(
            revision: string(fields["sha"], source, "commit.sha"),
            released_at: parsed_time(committer&.[]("date"))
          )
        end

        sig { params(value: Object, source: String, field: String).returns(JsonObject) }
        def self.object(value, source, field)
          invalid!(source, field, "an object") unless value.is_a?(Hash)

          T.let(value, JsonObject)
        end
        private_class_method :object

        sig { params(value: Object, source: String, field: String).returns(T.nilable(JsonObject)) }
        def self.optional_object(value, source, field)
          object(value, source, field) unless value.nil?
        end
        private_class_method :optional_object

        sig { params(value: Object, source: String, field: String).returns(String) }
        def self.string(value, source, field)
          return value if value.is_a?(String)

          invalid!(source, field, "a string")
        end
        private_class_method :string

        sig { params(value: Object).returns(T.nilable(Time)) }
        def self.parsed_time(value)
          value = value.iso8601 if value.is_a?(Time)
          Time.parse(value) if value.is_a?(String)
        rescue ArgumentError
          nil
        end
        private_class_method :parsed_time

        sig { params(source: String, field: String, expected: String).returns(T.noreturn) }
        def self.invalid!(source, field, expected)
          raise Dependabot::PrivateSourceBadResponse.new(
            source, "Malformed Nix revision response: #{field} must be #{expected}"
          )
        end
        private_class_method :invalid!
      end
    end
  end
end
