# frozen_string_literal: true

require "uri"

module Functions
  class FileParser
    def initialize(lockfile_name:)
      @lockfile_name = lockfile_name
    end

    attr_reader :lockfile_name

    def parsed_gemfile(gemfile_name:)
      Bundler::Definition.build(gemfile_name, nil, {}).
        dependencies.select(&:current_platform?).
        reject { |dep| dep.source.is_a?(Bundler::Source::Gemspec) }.
        map { |dep| serialize_bundler_dependency(dep) }
    end

    def parsed_gemspec(gemspec_name:)
      Bundler.load_gemspec_uncached(gemspec_name).
        dependencies.
        map { |dep| serialize_bundler_dependency(dep) }
    end

    private

    def lockfile
      return @lockfile if defined?(@lockfile)

      @lockfile =
        begin
          return unless lockfile_name && File.exist?(lockfile_name)

          File.read(lockfile_name)
        end
    end

    def parsed_lockfile
      return unless lockfile

      @parsed_lockfile ||= Bundler::LockfileParser.new(lockfile)
    end

    def source_from_lockfile(dependency_name)
      parsed_lockfile&.specs&.find { |s| s.name == dependency_name }&.source
    end

    def source_for(dependency)
      source = dependency.source
      if lockfile && default_rubygems?(source)
        # If there's a lockfile and the Gemfile doesn't have anything
        # interesting to say about the source, check that.
        source = source_from_lockfile(dependency.name)
      end
      raise "Bad source: #{source}" unless sources.include?(source.class)

      return nil if default_rubygems?(source)

      details = { type: source.class.name.split("::").last.downcase }
      details.merge!(git_source_details(source)) if source.is_a?(Bundler::Source::Git)
      details[:url] = source.remotes.first.to_s if source.is_a?(Bundler::Source::Rubygems)
      details
    end

    def git_source_details(source)
      {
        url: source.uri,
        branch: source.branch,
        ref: source.ref
      }
    end

    RUBYGEMS_HOSTS = [
      "rubygems.org",
      "www.rubygems.org"
    ].freeze

    def default_rubygems?(source)
      return true if source.nil?
      return false unless source.is_a?(Bundler::Source::Rubygems)

      source.remotes.any? do |r|
        RUBYGEMS_HOSTS.include?(URI(r.to_s).host)
      end
    end

    def serialize_bundler_dependency(dependency)
      {
        name: dependency.name,
        requirement: dependency.requirement,
        groups: dependency.groups,
        source: source_for(dependency),
        type: dependency.type
      }
    end

    # Can't be a constant because some of these don't exist in bundler
    # 1.15, which used to cause issues on Heroku (causing exception on boot).
    # TODO: Check if this will be an issue with multiple bundler versions
    def sources
      [
        NilClass,
        Bundler::Source::Rubygems,
        Bundler::Source::Git,
        Bundler::Source::Path,
        Bundler::Source::Gemspec,
        Bundler::Source::Metadata
      ]
    end
  end
end
