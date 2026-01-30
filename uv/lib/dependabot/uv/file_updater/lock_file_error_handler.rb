# typed: strict
# frozen_string_literal: true

require "dependabot/errors"
require "dependabot/utils"
require "dependabot/uv/file_updater"

module Dependabot
  module Uv
    class FileUpdater < Dependabot::FileUpdaters::Base
      class LockFileErrorHandler
        extend T::Sig

        UV_UNRESOLVABLE_REGEX = T.let(/× No solution found when resolving dependencies.*[\s\S]*$/, Regexp)
        UV_BUILD_FAILED_REGEX = T.let(/× Failed to build.*[\s\S]*$/, Regexp)
        RESOLUTION_IMPOSSIBLE_ERROR = T.let("ResolutionImpossible", String)

        GIT_DEPENDENCY_UNREACHABLE_REGEX = T.let(%r{git clone.*(?<url>https?://[^\s]+)}, Regexp)
        GIT_REFERENCE_NOT_FOUND_REGEX = T.let(
          /Did not find branch or tag '(?<tag>[^\n"']+)'/m,
          Regexp
        )
        PYTHON_VERSION_ERROR_REGEX = T.let(
          /Requires-Python|requires-python|python_requires|Python version/i,
          Regexp
        )
        AUTH_ERROR_REGEX = T.let(
          /401|403|authentication|unauthorized|forbidden|HTTP status code: 40[13]/i,
          Regexp
        )
        TIMEOUT_ERROR_REGEX = T.let(
          /timed?\s*out|connection.*reset|read timeout|connect timeout/i,
          Regexp
        )
        NETWORK_ERROR_REGEX = T.let(
          /ConnectionError|NetworkError|SSLError|certificate verify failed/i,
          Regexp
        )
        PACKAGE_NOT_FOUND_REGEX = T.let(
          /No matching distribution found|package.*not found|No versions found/i,
          Regexp
        )
        UV_REQUIRED_VERSION_REGEX = T.let(
          /Required uv version `(?<required>[^`]+)` does not match the running version `(?<running>[^`]+)`/,
          Regexp
        )

        # Maximum number of lines to include in cleaned error messages.
        # This limit ensures error messages remain readable while providing enough
        # context for debugging. Most uv error messages convey the key information
        # within the first few lines.
        MAX_ERROR_LINES = T.let(10, Integer)

        sig { params(error: SharedHelpers::HelperSubprocessFailed).returns(T.noreturn) }
        def handle_uv_error(error)
          message = error.message

          handle_required_version_errors(message)
          handle_resolution_errors(message)
          handle_git_errors(message)
          handle_authentication_errors(message)
          handle_network_errors(message)
          handle_python_version_errors(message)
          handle_resource_errors(message)
          handle_package_not_found_errors(message)

          raise error
        end

        private

        sig { params(message: String).void }
        def handle_required_version_errors(message)
          return unless (version_match = message.match(UV_REQUIRED_VERSION_REGEX))

          raise Dependabot::ToolVersionNotSupported.new(
            "uv",
            T.must(version_match[:required]),
            T.must(version_match[:running])
          )
        end

        sig { params(message: String).void }
        def handle_resolution_errors(message)
          return unless message.include?("No solution found when resolving dependencies") ||
                        message.include?("Failed to build") ||
                        message.include?(RESOLUTION_IMPOSSIBLE_ERROR)

          match_unresolvable = message.scan(UV_UNRESOLVABLE_REGEX).last
          match_build_failed = message.scan(UV_BUILD_FAILED_REGEX).last

          if match_unresolvable
            formatted_error = extract_match_string(match_unresolvable) || message
            conflicting_deps = extract_conflicting_dependencies(formatted_error)
            raise Dependabot::UpdateNotPossible, conflicting_deps if conflicting_deps.any?

            raise Dependabot::DependencyFileNotResolvable, formatted_error
          end

          formatted_error = extract_match_string(match_build_failed) || message
          raise Dependabot::DependencyFileNotResolvable, formatted_error
        end

        sig { params(error_message: String).returns(T::Array[String]) }
        def extract_conflicting_dependencies(error_message)
          # Extract conflicting dependency names from the error message
          # Pattern: "Because <pkg>==<ver> depends on <dep>>=<ver> and your project depends on <dep>==<ver>"
          normalized_message = error_message.gsub(/\s+/, " ")
          conflict_pattern = /Because (\S+)==\S+ depends on (\S+)[><=!]+\S+ and your project depends on \2==\S+/

          match = normalized_message.match(conflict_pattern)
          return [] unless match

          [T.must(match[1]), T.must(match[2])].uniq
        end

        sig { params(message: String).void }
        def handle_git_errors(message)
          if (match = message.match(GIT_REFERENCE_NOT_FOUND_REGEX))
            tag = match.named_captures.fetch("tag")
            raise Dependabot::GitDependencyReferenceNotFound, "(unknown package at #{tag})"
          end

          return unless (match = message.match(GIT_DEPENDENCY_UNREACHABLE_REGEX))

          url = match.named_captures.fetch("url")
          raise Dependabot::GitDependenciesNotReachable, T.must(url)
        end

        sig { params(message: String).void }
        def handle_authentication_errors(message)
          return unless message.match?(AUTH_ERROR_REGEX)

          source = extract_source_from_message(message)
          raise Dependabot::PrivateSourceAuthenticationFailure, source
        end

        sig { params(message: String).void }
        def handle_network_errors(message)
          if message.match?(TIMEOUT_ERROR_REGEX)
            source = extract_source_from_message(message)
            raise Dependabot::PrivateSourceTimedOut, source
          end

          return unless message.match?(NETWORK_ERROR_REGEX)

          source = extract_source_from_message(message)
          if message.include?("certificate verify failed") || message.include?("SSLError")
            raise Dependabot::PrivateSourceCertificateFailure, source
          end

          raise Dependabot::DependencyFileNotResolvable,
                "Network error while resolving dependencies: #{clean_error_message(message)}"
        end

        sig { params(message: String).void }
        def handle_python_version_errors(message)
          return unless message.match?(PYTHON_VERSION_ERROR_REGEX)

          raise Dependabot::DependencyFileNotResolvable,
                "Python version incompatibility: #{clean_error_message(message)}"
        end

        sig { params(message: String).void }
        def handle_resource_errors(message)
          raise Dependabot::OutOfDisk if message.include?("[Errno 28] No space left on device")
          raise Dependabot::OutOfMemory if message.include?("MemoryError")
        end

        sig { params(message: String).void }
        def handle_package_not_found_errors(message)
          return unless message.match?(PACKAGE_NOT_FOUND_REGEX)

          raise Dependabot::DependencyFileNotResolvable, clean_error_message(message)
        end

        sig { params(match: T.untyped).returns(T.nilable(String)) }
        def extract_match_string(match)
          return nil unless match

          match.is_a?(Array) ? match.join : match.to_s
        end

        sig { params(message: String).returns(String) }
        def extract_source_from_message(message)
          urls = URI.extract(message, %w(http https))
          return T.must(urls.first).gsub(%r{/$}, "") if urls.any?

          "private source"
        end

        sig { params(message: String).returns(String) }
        def clean_error_message(message)
          message
            .gsub(/#{Regexp.escape(Utils::BUMP_TMP_DIR_PATH)}[^\s]*/o, "")
            .lines
            .reject { |line| line.strip.empty? }
            .first(MAX_ERROR_LINES)
            .join
            .strip
        end
      end
    end
  end
end
