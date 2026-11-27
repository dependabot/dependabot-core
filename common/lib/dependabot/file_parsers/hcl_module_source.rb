# typed: strong
# frozen_string_literal: true

require "digest"
require "uri"
require "sorbet-runtime"
require "dependabot/errors"
require "dependabot/git_commit_checker"
require "dependabot/source"

module Dependabot
  module FileParsers
    module HclModuleSource
      extend T::Sig

      RequirementSource = T.type_alias { T::Hash[Symbol, T.nilable(String)] }

      class Git < T::ImmutableStruct
        extend T::Sig

        const :url, String
        const :ref, T.nilable(String)
        const :proxy_url, T.nilable(String)

        sig { params(module_name: String).returns(String) }
        def dependency_name(module_name)
          source = Source.from_url(url)
          repository =
            if source
              "#{source.provider}::#{source.repo}"
            else
              "git_provider::repo_name/git_repo(#{Digest::SHA1.hexdigest(url)})"
            end

          [module_name, repository, ref].compact.join("::")
        end

        sig { returns(T.nilable(String)) }
        def version
          ref&.match(GitCommitChecker::VERSION_REGEX)&.named_captures&.fetch("version")
        end

        sig { returns(RequirementSource) }
        def to_requirement_source
          HclModuleSource.with_proxy_url({ type: "git", url: url, branch: nil, ref: ref }, proxy_url)
        end
      end

      class Registry < T::ImmutableStruct
        extend T::Sig

        const :registry_hostname, String
        const :module_identifier, String
        const :proxy_url, T.nilable(String)

        sig { returns(RequirementSource) }
        def to_requirement_source
          HclModuleSource.with_proxy_url(
            { type: "registry", registry_hostname: registry_hostname, module_identifier: module_identifier },
            proxy_url
          )
        end
      end

      class UrlKind < T::Enum
        enums do
          HttpArchive = new("http_archive")
          Mercurial = new("mercurial")
          S3 = new("s3")
        end
      end

      class Url < T::ImmutableStruct
        extend T::Sig

        const :url, String
        const :kind, UrlKind
        const :proxy_url, T.nilable(String)

        sig { returns(RequirementSource) }
        def to_requirement_source
          HclModuleSource.with_proxy_url({ type: kind.serialize, url: url }, proxy_url)
        end
      end

      class Interpolation < T::ImmutableStruct; end

      Variant = T.type_alias { T.any(Git, Registry, Url) }

      sig do
        params(
          source: String,
          default_registry: String,
          archive_extensions: T::Array[String],
          proxy_url: T.nilable(String)
        ).returns(T.nilable(T.any(Variant, Interpolation)))
      end
      def self.parse(source, default_registry:, archive_extensions:, proxy_url:)
        return Interpolation.new if interpolation?(source)
        return if source.start_with?(".")
        return git_from(source, proxy_url) if source.start_with?("github.com/", "bitbucket.org/", "git::", "git@")

        kind = url_kind(source, archive_extensions)
        return Url.new(url: source, kind: kind, proxy_url: proxy_url) if kind

        registry_from(source, default_registry, proxy_url)
      end

      sig { params(source: String).returns(T::Boolean) }
      def self.interpolation?(source)
        source.include?("${")
      end

      sig { params(url: T.nilable(String)).returns(String) }
      def self.terragrunt_name(url)
        # Preserve the error for sources without a URL, such as a registry source.
        Source.from_url(url)&.repo || T.must(url)
      end

      sig { params(fields: RequirementSource, proxy_url: T.nilable(String)).returns(RequirementSource) }
      def self.with_proxy_url(fields, proxy_url)
        fields[:proxy_url] = proxy_url if proxy_url
        fields
      end

      sig { params(source: String, proxy_url: T.nilable(String)).returns(Git) }
      def self.git_from(source, proxy_url)
        url = source.strip.gsub(/^git::/, "")
        url = "https://" + url unless url.start_with?("git@") || url.include?("://")

        bare_uri =
          if url.include?("git@")
            T.must(url.split("git@").last).sub(":", "/")
          else
            url.sub(%r{(?:\w{3,5})?://}, "")
          end

        query = URI.parse("https://" + bare_uri).query
        ref = URI.decode_www_form(query.to_s).to_h["ref"]&.split(%r{(?<!:)//})&.first
        Git.new(url: T.must(url.gsub("?#{query}", "").split(%r{(?<!:)//}).first), ref: ref, proxy_url: proxy_url)
      end
      private_class_method :git_from

      sig { params(source: String, default_registry: String, proxy_url: T.nilable(String)).returns(Registry) }
      def self.registry_from(source, default_registry, proxy_url)
        address = source.split("//").first
        # Preserve the legacy error when the source has no address at all.
        raise NoMethodError, "undefined method 'split' for nil" unless address

        parts = address.split("/")
        hostname, identifier =
          case parts.length
          when 3 then [default_registry, address]
          when 4 then [parts.fetch(0), parts.drop(1).join("/")]
          else raise DependencyFileNotEvaluatable, "Invalid registry source specified: '#{source}'"
          end
        Registry.new(registry_hostname: hostname.downcase, module_identifier: identifier, proxy_url: proxy_url)
      end
      private_class_method :registry_from

      sig { params(source: String, archive_extensions: T::Array[String]).returns(T.nilable(UrlKind)) }
      def self.url_kind(source, archive_extensions)
        return UrlKind::Mercurial if source.start_with?("hg::")
        return UrlKind::S3 if source.start_with?("s3::")

        raise "Unknown src: #{source}" if source.split("/").first&.include?("::")

        return unless source.start_with?("http")
        return UrlKind::HttpArchive if http_archive?(source, archive_extensions)

        raise "HTTP source, but not an archive!"
      end
      private_class_method :url_kind

      sig { params(source: String, archive_extensions: T::Array[String]).returns(T::Boolean) }
      def self.http_archive?(source, archive_extensions)
        path_uri = URI.parse(T.must(source.split(%r{(?<!:)//}).first))
        query_uri = URI.parse(source)

        archive_extensions.any? { |ext| path_uri.path&.end_with?(ext) } || query_uri.query.to_s.include?("archive=")
      end
      private_class_method :http_archive?
    end
  end
end
