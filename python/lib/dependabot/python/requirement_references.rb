# typed: strong
# frozen_string_literal: true

require "pathname"
require "sorbet-runtime"

require "dependabot/dependency_file"

module Dependabot
  module Python
    module RequirementReferences
      extend T::Sig

      CHILD_REQUIREMENT_REGEX = /^-r\s?(?<path>.*\.(?:txt|in))/
      CONSTRAINT_REGEX = /^-c\s?(?<path>.*\.(?:txt|in))/

      # Resolves the sibling paths a requirements file references via `-r`/`-c`, returning repo-relative
      # cleanpaths (matching fetched DependencyFile names).
      sig { params(file: Dependabot::DependencyFile).returns(T::Array[String]) }
      def self.paths(file)
        content = file.content
        return [] if content.nil?

        current_dir = File.dirname(file.name)
        referenced = content.scan(CHILD_REQUIREMENT_REGEX).flatten + content.scan(CONSTRAINT_REGEX).flatten

        referenced.map do |path|
          resolved = current_dir == "." ? path : File.join(current_dir, path)
          Pathname.new(resolved).cleanpath.to_path
        end
      end
    end
  end
end
