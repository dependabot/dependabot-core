# typed: strong
# frozen_string_literal: true

require "sawyer"
require "sorbet-runtime"
require "time"

module Dependabot
  module Clients
    # Typed view over the release fields returned by Octokit.
    class GithubRelease < T::ImmutableStruct
      extend T::Sig

      const :id, T.nilable(Integer)
      const :name, T.nilable(String)
      const :tag_name, String
      const :body, T.nilable(String)
      const :html_url, T.nilable(String)
      const :prerelease, T::Boolean
      const :published_at, T.nilable(Time)

      sig { params(resource: Sawyer::Resource).returns(T.nilable(GithubRelease)) }
      def self.from_resource(resource)
        tag_name = T.cast(resource[:tag_name], Object)
        return unless tag_name.is_a?(String)

        id = T.cast(resource[:id], Object)
        prerelease = T.cast(resource[:prerelease], Object)

        new(
          id: id.is_a?(Integer) ? id : nil,
          name: string_value(resource, :name),
          tag_name: tag_name,
          body: string_value(resource, :body),
          html_url: string_value(resource, :html_url),
          prerelease: prerelease == true,
          published_at: time_value(resource, :published_at)
        )
      end

      sig { params(resource: Sawyer::Resource, key: Symbol).returns(T.nilable(String)) }
      def self.string_value(resource, key)
        value = T.cast(resource[key], Object)
        value.is_a?(String) ? value : nil
      end
      private_class_method :string_value

      sig { params(resource: Sawyer::Resource, key: Symbol).returns(T.nilable(Time)) }
      def self.time_value(resource, key)
        value = T.cast(resource[key], Object)
        return value if value.is_a?(Time)
        return unless value.is_a?(String)

        Time.parse(value)
      rescue ArgumentError
        nil
      end
      private_class_method :time_value
    end
  end
end
