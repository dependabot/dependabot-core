# typed: strong
# frozen_string_literal: true

require "sorbet-runtime"

require "dependabot/file_updaters"
require "dependabot/file_updaters/base"

module Dependabot
  module AzurePipelines
    class FileUpdater < Dependabot::FileUpdaters::Base
      extend T::Sig

      sig { override.returns(T::Array[Regexp]) }
      def self.updated_files_regex
        raise NotImplemented
      end

      sig { override.returns(T::Array[Dependabot::DependencyFile]) }
      def updated_dependency_files
        raise NotImplemented
      end
    end
  end
end

Dependabot::FileUpdaters.register("azure_pipelines", Dependabot::AzurePipelines::FileUpdater)
