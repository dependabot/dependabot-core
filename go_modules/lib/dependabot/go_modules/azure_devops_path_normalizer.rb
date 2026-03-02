# typed: strong
# frozen_string_literal: true

require "sorbet-runtime"

module Dependabot
  module GoModules
    module AzureDevopsPathNormalizer
      extend T::Sig

      sig { params(name: String).returns(String) }
      def self.normalize(name)
        return name unless name.start_with?("dev.azure.com/")

        segments = name.split("/")
        return name if segments.length < 4

        normalized_segments = T.let([], T::Array[String])
        if segments[3] == "_git"
          normalized_segments.concat(segments)
        else
          normalized_segments.concat(segments[0, 3] || [])
          normalized_segments << "_git"
          normalized_segments.concat(segments[3..] || [])
        end

        git_index = normalized_segments.index("_git")
        return name unless git_index

        repo_index = git_index + 1
        repo_name = normalized_segments[repo_index]
        return name unless repo_name

        normalized_segments[repo_index] = repo_name.delete_suffix(".git")

        normalized_segments.join("/")
      end
    end
  end
end
