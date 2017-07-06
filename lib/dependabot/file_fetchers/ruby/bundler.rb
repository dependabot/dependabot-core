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
          lockfile = ::Bundler::LockfileParser.new(gemfile_lock)

          path_specs = lockfile.specs.select do |spec|
            spec.source.instance_of?(::Bundler::Source::Path)
          end

          fetched_files = []
          unfetchable_gems = []

          path_specs.each do |spec|
            file = File.join(spec.source.path, "#{spec.source.name}.gemspec")

            begin
              fetched_files << fetch_file_from_github(file)
            rescue Dependabot::DependencyFileNotFound
              unfetchable_gems << spec.name
            end
          end

          if unfetchable_gems.any?
            raise Dependabot::PathDependenciesNotReachable, unfetchable_gems
          end

          fetched_files
        end

        def gemfile_lock
          gemfile_lock = required_files.find { |f| f.name == "Gemfile.lock" }
          gemfile_lock.content
        end
      end
    end
  end
end
