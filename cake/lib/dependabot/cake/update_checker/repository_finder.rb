# frozen_string_literal: true

require "dependabot/errors"
require "dependabot/nuget/update_checker/repository_finder"
require "dependabot/shared_helpers"
require "inifile"

module Dependabot
  module Cake
    class UpdateChecker
      class RepositoryFinder < Dependabot::Nuget::UpdateChecker::RepositoryFinder # rubocop:disable Layout/LineLength
        def initialize(dependency:,
                       credentials:,
                       config_files: [],
                       cake_config:)
          super(dependency: dependency,
                credentials: credentials,
                config_files: config_files)
          @cake_config = cake_config
        end

        private

        attr_reader :cake_config

        def known_repositories
          return @known_repositories if @known_repositories

          @known_repositories = super
          # Include cake.config [NuGet.Source] values only if the url does not
          # exist in @known_repositories
          sources = config_sources.select do |s|
            @known_repositories.find { |kr| kr[:url] == s[:url] } .nil?
          end

          @known_repositories += sources
          @known_repositories
        end

        def directive_source
          # Details of Cake preprocessor directives is at
          # https://cakebuild.net/docs/fundamentals/preprocessor-directives
          # @example Directive
          #   #module nuget:https://myget.org/f/Cake/?package=Cake.Foo&version=0.1.0
          # @see #Dependabot::Cake::FileParser
          @dependency.requirements.
            map { |req| req[:metadata][:cake_directive][:url] }.compact
        end

        def config_sources
          # Details of Cake configuration is at
          # https://cakebuild.net/docs/fundamentals/configuration
          # Cake allows semicolons in values so escape them before using IniFile
          return [] unless cake_config

          config_content = cake_config.content.
                           gsub(/=\s*[^=\r\n]+/) do |value|
            value.gsub(";", "<semicolon>")
          end

          config_ini = IniFile.new(content: config_content)

          config_sources = config_ini.to_h.
                           select { |key, _| key[/NuGet/i] }.values.
                           reduce({}, :merge).
                           select { |key, _| key[/Source/i] }.values.
                           flat_map { |source| source.split("<semicolon>") }.
                           filter { |url| valid_url?(url) }.
                           map { |url| { url: url, token: nil } }.
                           uniq
          config_sources
        end

        def valid_url?(url)
          uri = URI.parse(url)
          uri.is_a?(URI::HTTP) || uri.is_a?(URI::HTTPS)
        rescue Addressable::URI::InvalidURIError
          false
        end
      end
    end
  end
end
