# typed: strict
# frozen_string_literal: true

require "dependabot/bazel/file_updater"

module Dependabot
  module Bazel
    class FileUpdater < Dependabot::FileUpdaters::Base
      class WorkspaceFileUpdater
        extend T::Sig

        sig do
          params(
            dependency_files: T::Array[Dependabot::DependencyFile],
            dependencies: T::Array[Dependabot::Dependency],
            credentials: T::Array[Dependabot::Credential]
          ).void
        end
        def initialize(dependency_files:, dependencies:, credentials:)
          @dependency_files = dependency_files
          @dependencies = dependencies
          @credentials = credentials
        end

        sig { returns(T::Array[Dependabot::DependencyFile]) }
        def updated_workspace_files
          workspace_files.filter_map do |file|
            updated_content = update_file_content(file)
            next if updated_content == T.must(file.content)

            file.dup.tap { |f| f.content = updated_content }
          end
        end

        private

        sig { returns(T::Array[Dependabot::DependencyFile]) }
        attr_reader :dependency_files

        sig { returns(T::Array[Dependabot::Dependency]) }
        attr_reader :dependencies

        sig { returns(T::Array[Dependabot::Credential]) }
        attr_reader :credentials

        sig { returns(T::Array[Dependabot::DependencyFile]) }
        def workspace_files
          @workspace_files ||= T.let(
            dependency_files.select do |f|
              f.name == "WORKSPACE" || f.name.end_with?("WORKSPACE.bazel")
            end,
            T.nilable(T::Array[Dependabot::DependencyFile])
          )
        end

        sig { params(file: Dependabot::DependencyFile).returns(String) }
        def update_file_content(file)
          content = T.must(file.content).dup

          dependencies.each do |dependency|
            content = update_dependency_in_content(content, dependency)
          end

          content
        end

        sig { params(content: String, dependency: Dependabot::Dependency).returns(String) }
        def update_dependency_in_content(content, dependency)
          return content unless dependency.package_manager == "bazel"

          case dependency_type(dependency)
          when :http_archive
            update_http_archive_declaration(content, dependency)
          when :git_repository
            update_git_repository_declaration(content, dependency)
          else
            content
          end
        end

        sig { params(dependency: Dependabot::Dependency).returns(Symbol) }
        def dependency_type(dependency)
          return :http_archive if dependency.requirements.any? { |req| req.dig(:source, :type) == "http_archive" }
          return :git_repository if dependency.requirements.any? { |req| req.dig(:source, :type) == "git_repository" }

          :unknown
        end

        sig { params(content: String, dependency: Dependabot::Dependency).returns(String) }
        def update_http_archive_declaration(content, dependency)
          new_version = dependency.version
          return content unless new_version

          escaped_name = Regexp.escape(dependency.name)

          http_archive_pattern = /http_archive\s*\(([^)]+?)\)/mx

          content.gsub(http_archive_pattern) do |match|
            function_content = T.must(Regexp.last_match(1))

            if /name\s*=\s*["']#{escaped_name}["']/.match?(function_content)
              updated_function_content = update_http_archive_attributes(function_content, dependency)
              "http_archive(#{updated_function_content})"
            else
              match
            end
          end
        rescue Dependabot::DependencyFileNotResolvable => e
          raise e
        rescue StandardError => e
          raise Dependabot::DependencyFileNotResolvable,
                "Failed to update http_archive for #{dependency.name}: #{e.message}"
        end

        sig { params(function_content: String, dependency: Dependabot::Dependency).returns(String) }
        def update_http_archive_attributes(function_content, dependency)
          updated_content = function_content.dup

          updated_content = update_archive_url(updated_content, dependency) if /url\s*=/.match?(updated_content)

          updated_content = update_archive_urls_array(updated_content, dependency) if /urls\s*=/.match?(updated_content)

          updated_content
        end

        sig { params(content: String, dependency: Dependabot::Dependency).returns(String) }
        def update_archive_url(content, dependency)
          old_version = dependency.previous_version
          new_version = dependency.version
          return content unless old_version && new_version

          content.gsub(/url\s*=\s*["']([^"']+)["']/) do
            url = T.must(Regexp.last_match(1))
            updated_url = transform_version_in_url(url, old_version, new_version)
            "url = \"#{updated_url}\""
          end
        end

        sig { params(content: String, dependency: Dependabot::Dependency).returns(String) }
        def update_archive_urls_array(content, dependency)
          old_version = dependency.previous_version
          new_version = dependency.version
          return content unless old_version && new_version

          content.gsub(/urls\s*=\s*\[(.*?)\]/m) do
            urls_content = T.must(Regexp.last_match(1))
            updated_urls_content = urls_content.gsub(/["']([^"']+)["']/) do
              url = T.must(Regexp.last_match(1))
              updated_url = transform_version_in_url(url, old_version, new_version)
              "\"#{updated_url}\""
            end
            "urls = [#{updated_urls_content}]"
          end
        end

        sig { params(url: String, old_version: String, new_version: String).returns(String) }
        def transform_version_in_url(url, old_version, new_version)
          return url.gsub(old_version, new_version) if url.include?(old_version)

          return url.gsub("v#{old_version}", "v#{new_version}") if url.include?("v#{old_version}")

          old_with_v = "v#{old_version}"
          return url.gsub(old_with_v, "v#{new_version}") if url.include?(old_with_v)

          url
        end

        sig { params(content: String, dependency: Dependabot::Dependency).returns(String) }
        def update_git_repository_declaration(content, dependency)
          new_version = dependency.version
          return content unless new_version

          escaped_name = Regexp.escape(dependency.name)

          git_repo_pattern = /git_repository\s*\(([^)]+?)\)/mx

          content.gsub(git_repo_pattern) do |match|
            function_content = T.must(Regexp.last_match(1))

            if /name\s*=\s*["']#{escaped_name}["']/.match?(function_content)
              updated_function_content = if /tag\s*=/.match?(function_content)
                                           function_content.gsub(
                                             /tag\s*=\s*["'][^"']*["']/,
                                             "tag = \"#{new_version}\""
                                           )
                                         elsif /commit\s*=/.match?(function_content)
                                           function_content.gsub(
                                             /commit\s*=\s*["'][^"']*["']/,
                                             "commit = \"#{new_version}\""
                                           )
                                         else
                                           function_content
                                         end
              "git_repository(#{updated_function_content})"
            else
              match
            end
          end
        end
      end
    end
  end
end
