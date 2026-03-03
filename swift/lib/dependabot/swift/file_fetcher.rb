# typed: strict
# frozen_string_literal: true

require "pathname"
require "sorbet-runtime"
require "dependabot/experiments"
require "dependabot/file_fetchers"
require "dependabot/file_fetchers/base"

module Dependabot
  module Swift
    class FileFetcher < Dependabot::FileFetchers::Base
      extend T::Sig

      XCODE_SPM_PACKAGE_RESOLVED_PATH = "project.xcworkspace/xcshareddata/swiftpm/Package.resolved"
      # Skip directories that are unlikely to contain Xcode projects and may be very large
      SKIP_DIRECTORIES = T.let(%w(.git .build Pods node_modules vendor .swiftpm).freeze, T::Array[String])
      MAX_SCAN_DEPTH = 10

      sig { override.params(filenames: T::Array[String]).returns(T::Boolean) }
      def self.required_files_in?(filenames)
        return true if filenames.include?("Package.swift")

        if Dependabot::Experiments.enabled?(:enable_swift_xcode_spm)
          return filenames.any? { |f| f.end_with?("Package.resolved") }
        end

        false
      end

      sig { override.returns(String) }
      def self.required_files_message
        if Dependabot::Experiments.enabled?(:enable_swift_xcode_spm)
          "Repo must contain a Package.swift configuration file or " \
            "an .xcodeproj directory with a Package.resolved file."
        else
          "Repo must contain a Package.swift configuration file."
        end
      end

      sig { override.returns(T::Array[DependencyFile]) }
      def fetch_files
        fetched_files = T.let([], T::Array[DependencyFile])

        manifest = package_manifest
        if manifest
          fetched_files << manifest
          resolved = package_resolved
          fetched_files << resolved if resolved
          return fetched_files
        end

        # Base class validates returned files against required_files_in? and raises if needed
        return fetched_files unless Dependabot::Experiments.enabled?(:enable_swift_xcode_spm)

        fetch_xcode_spm_files(fetched_files)
        fetched_files
      end

      private

      sig { returns(T.nilable(Dependabot::DependencyFile)) }
      def package_manifest
        @package_manifest ||= T.let(fetch_file_if_present("Package.swift"), T.nilable(DependencyFile))
      end

      sig { returns(T.nilable(DependencyFile)) }
      def package_resolved
        @package_resolved ||= T.let(fetch_file_if_present("Package.resolved"), T.nilable(DependencyFile))
      end

      sig { params(fetched_files: T::Array[DependencyFile]).void }
      def fetch_xcode_spm_files(fetched_files)
        xcodeproj_dirs.each do |xcodeproj_path|
          pbxproj = fetch_support_file(File.join(xcodeproj_path, "project.pbxproj"))
          fetched_files << pbxproj if pbxproj

          resolved = fetch_file_if_present(File.join(xcodeproj_path, XCODE_SPM_PACKAGE_RESOLVED_PATH))
          fetched_files << resolved if resolved
        end
      end

      sig { returns(T::Array[String]) }
      def xcodeproj_dirs
        @xcodeproj_dirs ||= T.let(
          scan_for_xcodeproj_dirs(".", 0),
          T.nilable(T::Array[String])
        )
      end

      sig { params(dir: String, depth: Integer).returns(T::Array[String]) }
      def scan_for_xcodeproj_dirs(dir, depth)
        return [] if depth > MAX_SCAN_DEPTH

        results = T.let([], T::Array[String])

        repo_contents(dir: dir, raise_errors: false).each do |entry|
          next unless entry.type == "dir"

          entry_path = Pathname.new(File.join(dir, entry.name)).cleanpath.to_path

          if entry.name.end_with?(".xcodeproj")
            results << entry_path
          elsif !SKIP_DIRECTORIES.include?(entry.name)
            results.concat(scan_for_xcodeproj_dirs(entry_path, depth + 1))
          end
        end

        results
      end
    end
  end
end

Dependabot::FileFetchers
  .register("swift", Dependabot::Swift::FileFetcher)
