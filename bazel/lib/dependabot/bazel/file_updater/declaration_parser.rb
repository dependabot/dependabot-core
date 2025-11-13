# typed: strong
# frozen_string_literal: true

require "sorbet-runtime"
require "dependabot/bazel/file_updater"

module Dependabot
  module Bazel
    class FileUpdater < Dependabot::FileUpdaters::Base
      class DeclarationParser
        extend T::Sig

        sig { params(declaration_text: String).returns(T::Hash[Symbol, String]) }
        def self.parse_bazel_dep(declaration_text)
          attributes = {}

          name_match = declaration_text.match(/name\s*=\s*["']([^"']+)["']/)
          attributes[:name] = name_match[1] if name_match

          version_match = declaration_text.match(/version\s*=\s*["']([^"']+)["']/)
          attributes[:version] = version_match[1] if version_match

          dev_dep_match = declaration_text.match(/dev_dependency\s*=\s*(True|False)/)
          attributes[:dev_dependency] = dev_dep_match[1] if dev_dep_match

          repo_name_match = declaration_text.match(/repo_name\s*=\s*["']([^"']+)["']/)
          attributes[:repo_name] = repo_name_match[1] if repo_name_match

          attributes
        end

        sig { params(declaration_text: String).returns(T::Hash[Symbol, String]) }
        def self.parse_http_archive(declaration_text)
          attributes = {}

          name_match = declaration_text.match(/name\s*=\s*["']([^"']+)["']/)
          attributes[:name] = name_match[1] if name_match

          url_match = declaration_text.match(/url\s*=\s*["']([^"']+)["']/)
          attributes[:url] = url_match[1] if url_match

          urls_match = declaration_text.match(/urls\s*=\s*\[(.*?)\]/m)
          attributes[:urls] = urls_match[1] if urls_match

          sha256_match = declaration_text.match(/sha256\s*=\s*["']([^"']+)["']/)
          attributes[:sha256] = sha256_match[1] if sha256_match

          strip_prefix_match = declaration_text.match(/strip_prefix\s*=\s*["']([^"']+)["']/)
          attributes[:strip_prefix] = strip_prefix_match[1] if strip_prefix_match

          attributes
        end

        sig { params(declaration_text: String).returns(T::Hash[Symbol, String]) }
        def self.parse_git_repository(declaration_text)
          attributes = {}

          name_match = declaration_text.match(/name\s*=\s*["']([^"']+)["']/)
          attributes[:name] = name_match[1] if name_match

          remote_match = declaration_text.match(/remote\s*=\s*["']([^"']+)["']/)
          attributes[:remote] = remote_match[1] if remote_match

          tag_match = declaration_text.match(/tag\s*=\s*["']([^"']+)["']/)
          attributes[:tag] = tag_match[1] if tag_match

          commit_match = declaration_text.match(/commit\s*=\s*["']([^"']+)["']/)
          attributes[:commit] = commit_match[1] if commit_match

          branch_match = declaration_text.match(/branch\s*=\s*["']([^"']+)["']/)
          attributes[:branch] = branch_match[1] if branch_match

          attributes
        end
      end
    end
  end
end
