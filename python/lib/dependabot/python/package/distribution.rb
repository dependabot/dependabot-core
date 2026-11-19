# typed: strong
# frozen_string_literal: true

require "json"
require "time"
require "uri"
require "cgi/escape"
require "nokogiri"
require "sorbet-runtime"
require "dependabot/errors"

module Dependabot
  module Python
    module Package
      class Distribution < T::ImmutableStruct
        extend T::Sig

        ObjectHash = T.type_alias { T::Hash[String, Object] }

        const :version_string, String
        const :released_at, T.nilable(Time), default: nil
        const :requires_python, T.nilable(String), default: nil
        const :python_version, T.nilable(String), default: nil
        const :yanked, T::Boolean, default: false
        const :yanked_reason, T.nilable(String), default: nil
        const :downloads, Integer, default: -1
        const :url, T.nilable(String), default: nil
        const :package_type, T.nilable(String), default: nil

        sig { params(value: Object, version_string: String, context: String).returns(Distribution) }
        def self.from_pypi(value, version_string:, context:)
          fields = object(value, context)
          new(
            version_string: version_string,
            released_at: timestamp(fields["upload_time"], "#{context}.upload_time"),
            requires_python: optional_string(fields["requires_python"], "#{context}.requires_python"),
            python_version: optional_string(fields["python_version"], "#{context}.python_version"),
            yanked: boolean(fields["yanked"], "#{context}.yanked"),
            yanked_reason: optional_string(fields["yanked_reason"], "#{context}.yanked_reason"),
            downloads: downloads(fields["downloads"], "#{context}.downloads"),
            url: optional_string(fields["url"], "#{context}.url"),
            package_type: optional_string(fields["packagetype"], "#{context}.packagetype")
          )
        end

        sig do
          params(value: Object, version_string: String, context: String, project_url: String).returns(Distribution)
        end
        def self.from_simple(value, version_string:, context:, project_url:)
          fields = object(value, context)
          withdrawn = fields["yanked"]
          yanked = withdrawn.is_a?(String) || boolean(withdrawn, "#{context}.yanked")
          new(
            version_string: version_string,
            released_at: timestamp(fields["upload-time"], "#{context}.upload-time"),
            requires_python: optional_string(fields["requires-python"], "#{context}.requires-python"),
            yanked: yanked,
            yanked_reason: withdrawn.is_a?(String) ? withdrawn : nil,
            url: resolve_url(optional_string(fields["url"], "#{context}.url"), project_url, "#{context}.url")
          )
        end

        sig do
          params(
            link: Nokogiri::XML::Node, version_string: String, context: String, project_url: String
          ).returns(Distribution)
        end
        def self.from_html(link, version_string:, context:, project_url:)
          requirement = optional_string(T.cast(link["data-requires-python"], Object), "#{context}.data-requires-python")
          reason = optional_string(T.cast(link["data-yanked"], Object), "#{context}.data-yanked")
          withdrawn = !T.cast(link.attribute("data-yanked"), Object).nil?
          new(
            version_string: version_string,
            requires_python: requirement ? CGI.unescapeHTML(requirement) : nil,
            yanked: withdrawn,
            yanked_reason: reason,
            url: resolve_url(
              optional_string(T.cast(link["href"], Object), "#{context}.href"),
              project_url,
              "#{context}.href"
            )
          )
        end

        sig { params(format: String, source_url: String).returns(String) }
        def self.context(format, source_url)
          uri = URI.parse(source_url)
          uri.userinfo = nil
          uri.query = nil
          uri.fragment = nil
          "#{format} registry #{String(uri)}"
        rescue URI::InvalidURIError
          invalid(format, "registry URL is invalid")
        end

        sig { params(content: String, context: String).returns(Object) }
        def self.parse_json(content, context)
          T.cast(JSON.parse(content), Object)
        rescue JSON::ParserError
          invalid(context, "must contain valid JSON")
        end

        sig { params(value: Object, context: String).returns(ObjectHash) }
        def self.object(value, context)
          invalid(context, "must be an object") unless value.is_a?(Hash)

          value.to_h do |raw_key, raw_value|
            key = T.cast(raw_key, Object)
            invalid(context, "keys must be strings") unless key.is_a?(String)

            [key, T.cast(raw_value, Object)]
          end
        end

        sig { params(value: Object, context: String).returns(T::Array[Object]) }
        def self.array(value, context)
          invalid(context, "must be an array") unless value.is_a?(Array)

          value.map { |entry| T.cast(entry, Object) }
        end

        sig { params(value: Object, context: String).returns(T.nilable(String)) }
        def self.optional_string(value, context)
          return if value.nil?
          return value if value.is_a?(String)

          invalid(context, "must be a string or nil")
        end

        sig { params(context: String, message: String).returns(T.noreturn) }
        def self.invalid(context, message)
          raise DependencyFileNotResolvable.new("#{context} #{message}"), cause: nil
        end

        sig { params(value: Object, context: String).returns(T.nilable(Time)) }
        def self.timestamp(value, context)
          text = optional_string(value, context)
          return if text.nil?

          Time.parse(text)
        rescue ArgumentError
          invalid(context, "must be a valid timestamp")
        end
        private_class_method :timestamp

        sig { params(value: Object, context: String).returns(T::Boolean) }
        def self.boolean(value, context)
          case value
          when nil, false then false
          when true then true
          else invalid(context, "must be a boolean or nil")
          end
        end
        private_class_method :boolean

        sig { params(value: Object, context: String).returns(Integer) }
        def self.downloads(value, context)
          return -1 if value.nil?
          return value if value.is_a?(Integer)

          invalid(context, "must be an integer or nil")
        end
        private_class_method :downloads

        sig { params(url: T.nilable(String), project_url: String, context: String).returns(T.nilable(String)) }
        def self.resolve_url(url, project_url, context)
          return if url.nil?

          resolved = URI.join(project_url, url)
          resolved.user = nil
          resolved.password = nil
          String(resolved)
        rescue URI::InvalidURIError
          invalid(context, "must be a valid URL")
        end
        private_class_method :resolve_url
      end
    end
  end
end
