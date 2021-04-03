# frozen_string_literal: true

# TODO: File and specs need to be updated

require "dependabot/file_updaters"
require "dependabot/file_updaters/base"
require "dependabot/errors"

module Dependabot
  module Pub
    class FileUpdater < Dependabot::FileUpdaters::Base
      def self.updated_files_regex
        [/^pubspec\.yaml$/, /^pubspec\.lock$/]
      end

      def updated_dependency_files
        updated_files = []

        pubspec_file_pairs.each do |files|
          next unless file_changed?(files.yaml) || file_changed?(files.lock)

          updated_contents = updated_pubspec_file_contents(files)
          content_changed = false

          if updated_contents.yaml != files.yaml.content
            content_changed = true
            updated_files << updated_file(file: files.yaml, content: updated_contents.yaml)
          end

          if updated_contents.lock == files.lock.content
            content_changed = true
            updated_files << updated_file(file: files.lock, content: updated_contents.lock)
          end

          raise "Content didn't change!" unless content_changed
        end

        raise "No files changed!" if updated_files.none?

        updated_files
      end

      private

      def updated_pubspec_file_contents(files)
        content = file.content.dup

        reqs = dependency.requirements.zip(dependency.previous_requirements).
               reject { |new_req, old_req| new_req == old_req }

        # Loop through each changed requirement and update the files
        reqs.each do |new_req, old_req|
          raise "Bad req match" unless new_req[:file] == old_req[:file]
          next unless new_req.fetch(:file) == file.name

          case new_req[:source][:type]
          when "git"
            update_git_declaration(new_req, old_req, content, file.name)
          when "registry"
            update_registry_declaration(new_req, old_req, content)
          else
            raise "Don't know how to update a #{new_req[:source][:type]} "\
                  "declaration!"
          end
        end

        content
      end

      def update_git_declaration(new_req, old_req, updated_content, filename)
        url = old_req.fetch(:source)[:url].gsub(%r{^https://}, "")
        tag = old_req.fetch(:source)[:ref]
        url_regex = /#{Regexp.quote(url)}.*ref=#{Regexp.quote(tag)}/

        declaration_regex = git_declaration_regex(filename)

        updated_content.sub!(declaration_regex) do |regex_match|
          regex_match.sub(url_regex) do |url_match|
            url_match.sub(old_req[:source][:ref], new_req[:source][:ref])
          end
        end
      end

      def update_registry_declaration(new_req, old_req, updated_content)
        updated_content.sub!(registry_declaration_regex) do |regex_match|
          regex_match.sub(/version\s*=.*/) do |req_line_match|
            req_line_match.sub(old_req[:requirement], new_req[:requirement])
          end
        end
      end

      def dependency
        # Terraform updates will only ever be updating a single dependency
        dependencies.first
      end

      def pubspec_file_pairs
        pairs = []
        pubspec_yaml_files.each do |f|
          lock_file = pubspec_lock_files.find { |l| f.directory == l.directory }
          next unless lock_file

          pairs << {
            yaml: f,
            lock: lock_file
          }
        end
        pairs
      end

      def pubspec_yaml_files
        dependency_files.select { |f| f.name.end_with?("pubspec.yaml") }
      end

      def pubspec_lock_files
        dependency_files.select { |f| f.name.end_with?("pubspec.lock") }
      end

      def check_required_files
        return if [*pubspec_yaml_files].any?

        raise "No pubspec.yaml configuration file!"
      end

      # def registry_declaration_regex
      #   /
      #     (?<=\{)
      #     (?:(?!^\}).)*
      #     source\s*=\s*["']#{Regexp.escape(dependency.name)}["']
      #     (?:(?!^\}).)*
      #   /mx
      # end

      # def git_declaration_regex(filename)
      #   # For terragrunt dependencies there's not a lot we can base the
      #   # regex on. Just look for declarations within a `pub` block
      #   return /pub\s*\{(?:(?!^\}).)*/m if filename.end_with?(".tfvars")

      #   # For modules we can do better - filter for module blocks that use the
      #   # name of the dependency
      #   /
      #     module\s+["']#{Regexp.escape(dependency.name)}["']\s*\{
      #     (?:(?!^\}).)*
      #   /mx
      # end
    end
  end
end

Dependabot::FileUpdaters.
  register("pub", Dependabot::Pub::FileUpdater)
