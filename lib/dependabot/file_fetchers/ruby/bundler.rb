# frozen_string_literal: true
require "dependabot/file_fetchers/base"

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

          path_specs.map do |spec|
            dir, base = spec.source.path.split
            file = File.join(dir, base, "#{base}.gemspec")

            # TODO: Handle bad paths, probably by catching GitHub errors
            fetch_file_from_github(file)
          end
        end

        def gemfile_lock
          gemfile_lock = required_files.find { |f| f.name == "Gemfile.lock" }
          gemfile_lock.content
        end
      end
    end
  end
end
