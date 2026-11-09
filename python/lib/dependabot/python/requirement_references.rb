# typed: strong
# frozen_string_literal: true

require "pathname"
require "sorbet-runtime"

require "dependabot/dependency_file"
require "dependabot/python/shared_file_fetcher"

module Dependabot
  module Python
    module RequirementReferences
      extend T::Sig

      # Resolves the sibling paths a requirements file references via `-r`/`-c`, returning repo-relative
      # cleanpaths (matching fetched DependencyFile names).
      #
      # Reuses SharedFileFetcher's reference regexes so callers see exactly the children the file fetcher pulled in.
      sig { params(file: Dependabot::DependencyFile).returns(T::Array[String]) }
      def self.paths(file)
        content = file.content
        return [] if content.nil?

        current_dir = File.dirname(file.name)
        referenced =
          content.scan(Dependabot::Python::SharedFileFetcher::CHILD_REQUIREMENT_REGEX).flatten +
          content.scan(Dependabot::Python::SharedFileFetcher::CONSTRAINT_REGEX).flatten

        referenced.map do |path|
          resolved = current_dir == "." ? path : File.join(current_dir, path)
          Pathname.new(resolved).cleanpath.to_path
        end
      end
    end
  end
end
