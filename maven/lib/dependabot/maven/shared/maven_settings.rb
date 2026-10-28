# typed: strong
# frozen_string_literal: true

require "tempfile"
require "uri"
require "sorbet-runtime"

module Dependabot
  module Maven
    module Shared
      # Builds the temporary Maven `settings.xml` files passed to native `mvn` runs with `-s`.
      # They keep the proxy block from the baked `~/.m2/settings.xml` (the Dependabot proxy
      # injects registry auth, so no credentials are written here) and can add a mirror and
      # extra repositories.
      module MavenSettings
        extend T::Sig

        PROXIES_XML = <<~XML
          <proxies>
            <proxy>
              <id>dependabot-proxy</id>
              <active>true</active>
              <protocol>http</protocol>
              <host>${env.PROXY_HOST}</host>
              <port>1080</port>
            </proxy>
          </proxies>
        XML

        # A settings `<mirror>` that routes matching repositories to one registry.
        class Mirror < T::ImmutableStruct
          const :id, String
          const :url, String
          const :mirror_of, String
        end

        # Writes a settings file, yields its path, and deletes it afterwards.
        sig do
          type_parameters(:R)
            .params(
              mirror: T.nilable(Mirror),
              repository_urls: T::Array[String],
              proxy: T::Boolean,
              blk: T.proc.params(path: String).returns(T.type_parameter(:R))
            )
            .returns(T.type_parameter(:R))
        end
        def self.with_file(mirror: nil, repository_urls: [], proxy: true, &blk)
          file = Tempfile.new(["dependabot-mvn-settings", ".xml"])
          file.write(xml(mirror: mirror, repository_urls: repository_urls, proxy: proxy))
          file.close
          yield T.must(file.path)
        ensure
          file&.close!
        end

        sig do
          params(mirror: T.nilable(Mirror), repository_urls: T::Array[String], proxy: T::Boolean).returns(String)
        end
        def self.xml(mirror: nil, repository_urls: [], proxy: true)
          sections = proxy ? [PROXIES_XML] : []
          sections << mirrors_xml(mirror) if mirror
          sections << repositories_xml(repository_urls) if repository_urls.any?
          "<settings>\n#{sections.join.gsub(/^(?=.)/, '  ')}</settings>\n"
        end

        # The environment the proxy block reads its host from.
        sig { returns(T::Hash[String, String]) }
        def self.proxy_env
          proxy = ENV.fetch("HTTPS_PROXY", nil)
          proxy ? { "PROXY_HOST" => URI.parse(proxy).host.to_s } : {}
        end

        sig { params(mirror: Mirror).returns(String) }
        def self.mirrors_xml(mirror)
          <<~XML
            <mirrors>
              <mirror>
                <id>#{mirror.id.encode(xml: :text)}</id>
                <mirrorOf>#{mirror.mirror_of.encode(xml: :text)}</mirrorOf>
                <url>#{mirror.url.encode(xml: :text)}</url>
              </mirror>
            </mirrors>
          XML
        end
        private_class_method :mirrors_xml

        # Adds each URL as both a repository and a plugin repository, in an always-active profile.
        sig { params(urls: T::Array[String]).returns(String) }
        def self.repositories_xml(urls)
          entries = urls.each_with_index.map do |url, index|
            "<id>dependabot-registry-#{index + 1}</id><url>#{url.encode(xml: :text)}</url>"
          end
          <<~XML
            <profiles>
              <profile>
                <id>dependabot-registries</id>
                <repositories>#{entries.map { |e| "<repository>#{e}</repository>" }.join}</repositories>
                <pluginRepositories>#{entries.map { |e| "<pluginRepository>#{e}</pluginRepository>" }.join}</pluginRepositories>
              </profile>
            </profiles>
            <activeProfiles>
              <activeProfile>dependabot-registries</activeProfile>
            </activeProfiles>
          XML
        end
        private_class_method :repositories_xml
      end
    end
  end
end
