# frozen_string_literal: true

require "nokogiri"

require "dependabot/dependency"
require "dependabot/file_parsers"
require "dependabot/file_parsers/base"
require "dependabot/paket/native_helpers"

# For details on how dotnet handles version constraints, see:
# https://docs.microsoft.com/en-us/nuget/reference/package-versioning
module Dependabot
  module Paket
    class FileParser < Dependabot::FileParsers::Base
      require "dependabot/file_parsers/base/dependency_set"
      require_relative "file_parser/paket_lockfile_parser"

      PAKET_DEPENDENCIES_FILE = "paket.dependencies"
      PAKET_LOCK_FILE = "paket.lock"

      def parse
        dependency_set = DependencySet.new
        dependency_set += lockfile_dependencies
        dependency_set.dependencies
      end

      private

      def check_required_files
        return if paket_dependencies.any? && paket_lock.any?
        format = "No %s or %s!" % [PAKET_DEPENDENCIES_FILE, PAKET_LOCK_FILE]
        raise format
      end

      def paket_dependencies
        dependency_files.select { |df| df.name.eql?(PAKET_DEPENDENCIES_FILE) }
      end

      def paket_lock
        dependency_files.select { |df| df.name.eql?(PAKET_LOCK_FILE) }
      end

      def lockfile_parser
        @lockfile_parser ||= PaketLockfileParser.new(
          dependency_files: dependency_files
        )
      end

      def lockfile_dependencies
        DependencySet.new(lockfile_parser.parse)
      end

    end
  end
end

Dependabot::FileParsers.register("paket", Dependabot::Paket::FileParser)
