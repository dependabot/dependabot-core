# typed: strict
# frozen_string_literal: true

require "json"
require "sorbet-runtime"
require "toml-rb"

require "dependabot/credential"
require "dependabot/dependency_file"
require "dependabot/error_report_context"
require "dependabot/shared_helpers"

module Dependabot
  module Python
    # Attaches debug-only `error-context` to failed Poetry and Pipenv commands. Only an allowlisted
    # command name and the index hosts are reported: command lines, index URLs and helper output can
    # contain credentials or private package names.
    module SubprocessErrorContext
      extend T::Sig

      PYPI_HOST = "pypi.org"

      SUBCOMMANDS = T.let(
        {
          "poetry" => %w(add config install lock show update),
          "pipenv" => %w(graph install lock requirements sync update upgrade),
          "pyenv" => %w(install local)
        }.freeze,
        T::Hash[String, T::Array[String]]
      )

      sig do
        params(
          error: SharedHelpers::HelperSubprocessFailed,
          command: String,
          dependency_files: T::Array[Dependabot::DependencyFile],
          credentials: T::Array[Dependabot::Credential]
        ).void
      end
      def self.attach(error, command:, dependency_files:, credentials:)
        ErrorReportContext.attach(
          error,
          {
            command_name: command_name(command),
            index_hosts: index_hosts(dependency_files, credentials)
          }
        )
      rescue StandardError => e
        # Building diagnostics must never mask the original failure
        Dependabot.logger.debug("Failed to build error context: #{e.class}")
      end

      sig { params(command: String).returns(T.nilable(String)) }
      def self.command_name(command)
        words = command.split
        words.shift(2) if words.first(2) == %w(pyenv exec)
        tool = words.first
        subcommands = tool && SUBCOMMANDS[tool]
        return unless subcommands

        subcommand = words[1]
        subcommand && subcommands.include?(subcommand) ? "#{tool} #{subcommand}" : tool
      end

      sig do
        params(
          dependency_files: T::Array[Dependabot::DependencyFile],
          credentials: T::Array[Dependabot::Credential]
        ).returns(T::Array[String])
      end
      def self.index_hosts(dependency_files, credentials)
        urls = credentials.select { |cred| cred["type"] == "python_index" }.filter_map { |cred| cred["index-url"] }
        urls += dependency_files.flat_map { |file| source_urls(file) }

        hosts = urls.filter_map { |url| host(url) }.uniq
        hosts.empty? ? [PYPI_HOST] : hosts
      end

      sig { params(file: Dependabot::DependencyFile).returns(T::Array[String]) }
      def self.source_urls(file)
        content = file.content
        return [] unless content

        sources = case file.name
                  when "Pipfile" then TomlRB.parse(content)["source"]
                  when "Pipfile.lock" then JSON.parse(content).dig("_meta", "sources")
                  when "pyproject.toml" then TomlRB.parse(content).dig("tool", "poetry", "source")
                  end
        return [] unless sources.is_a?(Array)

        sources.filter_map { |source| source["url"] if source.is_a?(Hash) && source["url"].is_a?(String) }
      rescue TomlRB::Error, JSON::ParserError
        []
      end

      # Userinfo is stripped from the authority first so that URLs with templated credentials
      # (e.g. `https://${USER}:${TOKEN}@host/simple`) still yield their host. The authority
      # ends at the first `/`, `?` or `#`, so query strings and fragments are never read.
      sig { params(url: String).returns(T.nilable(String)) }
      def self.host(url)
        url = url.strip
        scheme_end = url.index("://")
        return unless scheme_end

        authority_start = scheme_end + 3
        authority_end = %w(/ ? #).filter_map { |char| url.index(char, authority_start) }.min || url.length
        authority = T.must(url[authority_start...authority_end]).rpartition("@").last
        host = ErrorReportContext.host_for("#{url[0...authority_start]}#{authority}#{url[authority_end..]}")
        host == ErrorReportContext::REDACTED ? nil : host
      end
      private_class_method :command_name, :index_hosts, :source_urls, :host
    end
  end
end
