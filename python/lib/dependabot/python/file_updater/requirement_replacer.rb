# typed: true
# frozen_string_literal: true

require "dependabot/dependency"
require "dependabot/python/requirement_parser"
require "dependabot/python/file_updater"
require "dependabot/shared_helpers"
require "dependabot/python/native_helpers"
require "dependabot/python/name_normaliser"

module Dependabot
  module Python
    class FileUpdater
      class RequirementReplacer
        PACKAGE_NOT_FOUND_ERROR = "PackageNotFoundError"

        CERTIFICATE_VERIFY_FAILED = /CERTIFICATE_VERIFY_FAILED/

        def initialize(content:, dependency_name:, old_requirement:,
                       new_requirement:, new_hash_version: nil, index_urls: nil)
          @content          = content
          @dependency_name  = normalise(dependency_name)
          @old_requirement  = old_requirement
          @new_requirement  = new_requirement
          @new_hash_version = new_hash_version
          @index_urls = index_urls
        end

        def updated_content
          updated_content =
            content.gsub(original_declaration_replacement_regex) do |mtch|
              # If the "declaration" is setting an option (e.g., no-binary)
              # ignore it, since it isn't actually a declaration
              next mtch if Regexp.last_match&.pre_match&.match?(/--.*\z/)

              updated_dependency_declaration_string
            end

          raise "Expected content to change!" if old_requirement != new_requirement && content == updated_content

          updated_content
        end

        private

        attr_reader :content
        attr_reader :dependency_name
        attr_reader :old_requirement
        attr_reader :new_requirement
        attr_reader :new_hash_version

        def update_hashes?
          !new_hash_version.nil?
        end

        def updated_requirement_string
          new_req_string = new_requirement

          new_req_string = new_req_string.gsub(/,\s*/, ", ") if add_space_after_commas?

          if add_space_after_operators?
            new_req_string =
              new_req_string
              .gsub(/(#{RequirementParser::COMPARISON})\s*(?=\d)/o, '\1 ')
          end

          new_req_string
        end

        def updated_dependency_declaration_string
          old_req = old_requirement
          updated_string =
            if old_req
              original_dependency_declaration_string(old_req)
                .sub(RequirementParser::REQUIREMENTS, updated_requirement_string)
            else
              original_dependency_declaration_string(old_req)
                .sub(RequirementParser::NAME_WITH_EXTRAS) do |nm|
                  nm + updated_requirement_string
                end
            end

          return updated_string unless update_hashes? && requirement_includes_hashes?(old_req)

          updated_string.sub(
            RequirementParser::HASHES,
            package_hashes_for(
              name: dependency_name,
              version: new_hash_version,
              algorithm: hash_algorithm(old_req)
            ).join(hash_separator(old_req))
          )
        end

        def add_space_after_commas?
          original_dependency_declaration_string(old_requirement)
            .match(RequirementParser::REQUIREMENTS)
            .to_s.include?(", ")
        end

        def add_space_after_operators?
          original_dependency_declaration_string(old_requirement)
            .match(RequirementParser::REQUIREMENTS)
            .to_s.match?(/#{RequirementParser::COMPARISON}\s+\d/o)
        end

        def original_declaration_replacement_regex
          original_string =
            original_dependency_declaration_string(old_requirement)
          /(?<![\-\w\.\[])#{Regexp.escape(original_string)}(?![\-\w\.])/
        end

        def requirement_includes_hashes?(requirement)
          original_dependency_declaration_string(requirement)
            .match?(RequirementParser::HASHES)
        end

        def hash_algorithm(requirement)
          return unless requirement_includes_hashes?(requirement)

          original_dependency_declaration_string(requirement)
            .match(RequirementParser::HASHES)
            .named_captures.fetch("algorithm")
        end

        def hash_separator(requirement)
          return unless requirement_includes_hashes?(requirement)

          hash_regex = RequirementParser::HASH
          current_separator =
            original_dependency_declaration_string(requirement)
            .match(/#{hash_regex}((?<separator>\s*\\?\s*?)#{hash_regex})*/)
            .named_captures.fetch("separator")

          default_separator =
            original_dependency_declaration_string(requirement)
            .match(RequirementParser::HASH)
            .pre_match.match(/(?<separator>\s*\\?\s*?)\z/)
            .named_captures.fetch("separator")

          current_separator || default_separator
        end

        def package_hashes_for(name:, version:, algorithm:)
          index_urls = @index_urls || [nil]

          index_urls.map do |index_url|
            args = [name, version, algorithm]
            args << index_url unless index_url.nil?

            begin
              result = SharedHelpers.run_helper_subprocess(
                command: "pyenv exec python3 #{NativeHelpers.python_helper_path}",
                function: "get_dependency_hash",
                args: args
              )
            rescue SharedHelpers::HelperSubprocessFailed => e
              requirement_error_handler(e)

              raise unless e.message.include?("PackageNotFoundError")

              next
            end

            return result.map { |h| "--hash=#{algorithm}:#{h['hash']}" } if result.is_a?(Array)
          end

          raise Dependabot::DependencyFileNotResolvable, "Unable to find hashes for package #{name}"
        end

        def original_dependency_declaration_string(old_req)
          matches = []

          dec =
            if old_req.nil?
              regex = RequirementParser::INSTALL_REQ_WITHOUT_REQUIREMENT
              content.scan(regex) { matches << Regexp.last_match }
              matches.find { |m| normalise(m[:name]) == dependency_name }
            else
              regex = RequirementParser::INSTALL_REQ_WITH_REQUIREMENT
              content.scan(regex) { matches << Regexp.last_match }
              matches
                .select { |m| normalise(m[:name]) == dependency_name }
                .find { |m| requirements_match(m[:requirements], old_req) }
            end

          raise "Declaration not found for #{dependency_name}!" unless dec

          dec.to_s.strip
        end

        def normalise(name)
          NameNormaliser.normalise(name)
        end

        def requirements_match(req1, req2)
          req1&.split(",")&.map { |r| r.gsub(/\s/, "") }&.sort ==
            req2&.split(",")&.map { |r| r.gsub(/\s/, "") }&.sort
        end

        public

        def requirement_error_handler(error)
          Dependabot.logger.warn(error.message)

          return unless error.message.match?(CERTIFICATE_VERIFY_FAILED)

          msg = "Error resolving dependency."
          raise DependencyFileNotResolvable, msg
        end
      end
    end
  end
end
