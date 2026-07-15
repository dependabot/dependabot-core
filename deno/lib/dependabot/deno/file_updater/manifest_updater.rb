# typed: strict
# frozen_string_literal: true

require "sorbet-runtime"

require "dependabot/dependency"
require "dependabot/dependency_file"
require "dependabot/deno/file_updater"

module Dependabot
  module Deno
    class FileUpdater
      class ManifestUpdater
        extend T::Sig

        sig do
          params(
            dependencies: T::Array[Dependabot::Dependency],
            manifest: Dependabot::DependencyFile
          ).void
        end
        def initialize(dependencies:, manifest:)
          @dependencies = dependencies
          @manifest = manifest
        end

        sig { returns(String) }
        def updated_manifest_content
          content = T.must(manifest.content).dup

          dependencies.each do |dep|
            prev_reqs = (dep.previous_requirements || []).select { |r| r[:file] == manifest.name }
            new_reqs = dep.requirements.select { |r| r[:file] == manifest.name }

            prev_reqs.zip(new_reqs).each do |prev_req, new_req|
              content = apply_substitution(content, dep, prev_req, T.must(new_req))
            end
          end

          content
        end

        private

        sig { returns(T::Array[Dependabot::Dependency]) }
        attr_reader :dependencies

        sig { returns(Dependabot::DependencyFile) }
        attr_reader :manifest

        sig do
          params(
            content: String,
            dep: Dependabot::Dependency,
            prev_req: T::Hash[Symbol, T.anything],
            new_req: T::Hash[Symbol, T.anything]
          ).returns(String)
        end
        def apply_substitution(content, dep, prev_req, new_req)
          source = T.cast(prev_req[:source], T::Hash[Symbol, T.anything])
          source_type = T.cast(source[:type], String)
          prev_req_str = T.cast(prev_req[:requirement], T.nilable(String))
          new_req_str = T.cast(new_req[:requirement], T.nilable(String))

          base = "#{source_type}:#{dep.name}"
          old_specifier = prev_req_str ? "#{base}@#{prev_req_str}" : base
          new_specifier = "#{base}@#{new_req_str}"

          content.gsub(%r{#{Regexp.escape(old_specifier)}(?=["/])}, new_specifier)
        end
      end
    end
  end
end
