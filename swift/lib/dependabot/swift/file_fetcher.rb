# typed: strict
# frozen_string_literal: true

require "sorbet-runtime"
require "dependabot/experiments"
require "dependabot/file_fetchers"
require "dependabot/file_fetchers/base"
require "dependabot/swift/xcode_file_helpers"

module Dependabot
  module Swift
    class FileFetcher < Dependabot::FileFetchers::Base
      extend T::Sig

      XCODEPROJ_SUFFIX = ".xcodeproj"
      XCWORKSPACE_SUFFIX = ".xcworkspace"
      XCODE_SPM_PACKAGE_RESOLVED_PATH = "project.xcworkspace/xcshareddata/swiftpm/Package.resolved"
      XCWORKSPACE_PACKAGE_RESOLVED_PATH = "xcshareddata/swiftpm/Package.resolved"

      sig { override.params(filenames: T::Array[String]).returns(T::Boolean) }
      def self.required_files_in?(filenames)
        return true if filenames.include?("Package.swift")

        if Dependabot::Experiments.enabled?(:enable_swift_xcode_spm)
          return filenames.any? { |f| XcodeFileHelpers.xcode_resolved_path?(f) }
        end

        false
      end

      sig { override.returns(String) }
      def self.required_files_message
        if Dependabot::Experiments.enabled?(:enable_swift_xcode_spm)
          "Repo must contain a Package.swift configuration file or " \
            "an .xcodeproj/.xcworkspace directory with a Package.resolved file."
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

        xcworkspace_dirs.each do |workspace_path|
          workspace_data = fetch_support_file(File.join(workspace_path, "contents.xcworkspacedata"))
          fetched_files << workspace_data if workspace_data

          resolved = fetch_file_if_present(File.join(workspace_path, XCWORKSPACE_PACKAGE_RESOLVED_PATH))
          fetched_files << resolved if resolved
        end
      end

      sig { returns(T::Array[String]) }
      def xcodeproj_dirs
        @xcodeproj_dirs ||= T.let(
          discover_dirs_with_suffix(XCODEPROJ_SUFFIX),
          T.nilable(T::Array[String])
        )
      end

      sig { returns(T::Array[String]) }
      def xcworkspace_dirs
        @xcworkspace_dirs ||= T.let(
          discover_dirs_with_suffix(XCWORKSPACE_SUFFIX)
            .reject { |path| path.include?("#{XCODEPROJ_SUFFIX}/") },
          T.nilable(T::Array[String])
        )
      end

      sig { params(suffix: String).returns(T::Array[String]) }
      def discover_dirs_with_suffix(suffix)
        discovered = T.let([], T::Array[String])
        queue = T.let(["."], T::Array[String])
        visited = T.let({}, T::Hash[String, T::Boolean])
        index = T.let(0, Integer)

        while index < queue.length
          dir = T.must(queue[index])
          index += 1
          next if visited[dir]

          visited[dir] = true

          entries = repo_contents(dir: dir, raise_errors: false)
          entries.each do |entry|
            next unless entry.type == "dir"

            next_dir = dir == "." ? entry.name : File.join(dir, entry.name)
            if entry.name.end_with?(suffix)
              discovered << next_dir
            elsif !entry.name.start_with?(".")
              queue << next_dir
            end
          end
        end

        discovered.sort
      end
    end
  end
end

Dependabot::FileFetchers
  .register("swift", Dependabot::Swift::FileFetcher)
