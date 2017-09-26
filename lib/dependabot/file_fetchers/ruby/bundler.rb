# frozen_string_literal: true

require "dependabot/file_fetchers/base"
require "dependabot/errors"

module Dependabot
  module FileFetchers
    module Ruby
      class Bundler < Dependabot::FileFetchers::Base
        def self.required_files_in?(filenames)
          if filenames.include?("Gemfile.lock") &&
             !filenames.include?("Gemfile")
            return false
          end

          if filenames.any? { |name| name.match?(%r{^[^/]*\.gemspec$}) }
            return true
          end

          filenames.include?("Gemfile")
        end

        def self.required_files_message
          "Repo must contain either a Gemfile or a gemspec. " \
          "A Gemfile.lock may only be present if a Gemfile is."
        end

        private

        def fetch_files
          fetched_files = []
          fetched_files << gemfile unless gemfile.nil?
          fetched_files << lockfile unless lockfile.nil?
          fetched_files << gemspec unless gemspec.nil?
          fetched_files << ruby_version_file unless ruby_version_file.nil?
          fetched_files += path_gemspecs

          unless self.class.required_files_in?(fetched_files.map(&:name))
            raise "Invalid set of files: #{fetched_files.map(&:name)}"
          end

          fetched_files.uniq
        end

        def gemfile
          @gemfile ||= fetch_file_from_github("Gemfile")
        rescue Dependabot::DependencyFileNotFound
          raise unless gemspec
        end

        def lockfile
          @lockfile ||= fetch_file_from_github("Gemfile.lock")
        rescue Dependabot::DependencyFileNotFound
          nil
        end

        def gemspec
          return @gemspec if @gemspec_fetch_attempted
          @gemspec_fetch_attempted = true
          path = Pathname.new(directory).cleanpath.to_path
          gemspec =
            github_client.contents(repo, path: path, ref: commit).
            find { |file| file.name.end_with?(".gemspec") }

          return unless gemspec
          @gemspec = fetch_file_from_github(gemspec.name)
        end

        def ruby_version_file
          return unless gemfile
          return unless gemfile.content.include?(".ruby-version")
          fetch_file_from_github(".ruby-version")
        rescue Dependabot::DependencyFileNotFound
          nil
        end

        def path_gemspecs
          gemspec_files = []
          unfetchable_gems = []

          return [] unless lockfile
          ::Bundler::LockfileParser.new(lockfile.content).specs.each do |spec|
            next unless spec.source.instance_of?(::Bundler::Source::Path)

            file = File.join(spec.source.path, "#{spec.name}.gemspec")

            begin
              gemspec_files << fetch_file_from_github(file)
            rescue Dependabot::DependencyFileNotFound
              unfetchable_gems << spec.name
            end
          end

          if unfetchable_gems.any?
            raise Dependabot::PathDependenciesNotReachable, unfetchable_gems
          end

          gemspec_files
        end
      end
    end
  end
end
