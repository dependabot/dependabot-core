# frozen_string_literal: true
require "dependabot/file_fetchers/base"
require "dependabot/errors"

module Dependabot
  module FileFetchers
    module Ruby
      class Bundler < Dependabot::FileFetchers::Base
        def self.required_files
          %w(Gemfile Gemfile.lock)
        end

        private

        def extra_files
          fetched_files = []
          fetched_files += path_gemspecs
          fetched_files << ruby_version_file unless ruby_version_file.nil?
          fetched_files
        end

        def path_gemspecs
          gemspec_files = []
          unfetchable_gems = []

          ::Bundler::LockfileParser.new(gemfile_lock).specs.each do |spec|
            next unless spec.source.instance_of?(::Bundler::Source::Path)

            file = File.join(spec.source.path, "#{spec.source.name}.gemspec")

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

        def ruby_version_file
          return unless gemfile.include?(".ruby-version")
          fetch_file_from_github(".ruby-version")
        rescue Dependabot::DependencyFileNotFound
          nil
        end

        def gemfile_lock
          gemfile_lock = required_files.find { |f| f.name == "Gemfile.lock" }
          gemfile_lock.content
        end

        def gemfile
          gemfile = required_files.find { |f| f.name == "Gemfile" }
          gemfile.content
        end
      end
    end
  end
end
