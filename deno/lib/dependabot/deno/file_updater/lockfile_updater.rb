# typed: strict
# frozen_string_literal: true

require "json"
require "sorbet-runtime"

require "dependabot/dependency"
require "dependabot/dependency_file"
require "dependabot/errors"
require "dependabot/shared_helpers"
require "dependabot/deno/file_updater"
require "dependabot/deno/helpers"

module Dependabot
  module Deno
    class FileUpdater < Dependabot::FileUpdaters::Base
      class LockfileUpdater
        extend T::Sig

        MANIFEST_FILENAMES = T.let(%w(deno.json deno.jsonc).freeze, T::Array[String])
        LOCKFILE_FILENAME = "deno.lock"

        sig do
          params(
            dependencies: T::Array[Dependabot::Dependency],
            dependency_files: T::Array[Dependabot::DependencyFile],
            credentials: T::Array[Dependabot::Credential]
          ).void
        end
        def initialize(dependencies:, dependency_files:, credentials:)
          @dependencies = dependencies
          @dependency_files = dependency_files
          @credentials = credentials
        end

        sig { returns(String) }
        def updated_lockfile_content
          @updated_lockfile_content ||= T.let(
            regenerate_lockfile,
            T.nilable(String)
          )
        end

        private

        sig { returns(T::Array[Dependabot::Dependency]) }
        attr_reader :dependencies

        sig { returns(T::Array[Dependabot::DependencyFile]) }
        attr_reader :dependency_files

        sig { returns(T::Array[Dependabot::Credential]) }
        attr_reader :credentials

        sig { returns(String) }
        def regenerate_lockfile
          # Deno rewrites `deno.lock` holistically (not surgically) when its
          # input manifest references newer constraints. Don't try to
          # preserve unrelated entries here — that's deno install's job.
          #
          # Note on error detection: `deno install` exits 0 even when a
          # specifier can't be resolved (missing package, unsatisfiable
          # constraint) — it just silently leaves the lockfile unchanged.
          # The byte-equal check below is the primary defense; the rescue
          # wraps the rare-but-real cases where deno does exit non-zero
          # (malformed config, binary missing, filesystem errors).
          original_lockfile_content = T.must(lockfile.content)

          new_content =
            begin
              SharedHelpers.in_a_temporary_directory do |dir|
                write_temporary_files(dir.to_s)
                Helpers.run_deno_command("install", "--frozen=false", dir: dir.to_s)
                File.read(File.join(dir.to_s, LOCKFILE_FILENAME))
              end
            rescue Helpers::DenoCommandError => e
              raise Dependabot::DependencyFileNotResolvable, e.message
            end

          if new_content == original_lockfile_content
            raise Dependabot::DependencyFileNotResolvable,
                  "deno install did not change #{LOCKFILE_FILENAME}; manifest bump did not take effect"
          end

          new_content
        end

        sig { params(dir: String).void }
        def write_temporary_files(dir)
          File.write(File.join(dir, manifest.name), updated_manifest_content)
          File.write(File.join(dir, LOCKFILE_FILENAME), T.must(lockfile.content))
        end

        sig { returns(String) }
        def updated_manifest_content
          # Re-apply the same gsub FileUpdater uses. Duplicates ~20 lines but
          # avoids exposing FileUpdater's private method; if the manifest
          # update logic grows, extract a shared ManifestUpdater class.
          content = T.must(manifest.content).dup
          dependencies.each do |dep|
            prev_reqs = dep.previous_requirements || []
            new_reqs = dep.requirements
            prev_reqs.zip(new_reqs).each do |prev_req, new_req|
              next unless prev_req && new_req
              next unless prev_req[:file] == manifest.name

              source_type = prev_req[:source][:type]
              prev_req_str = prev_req[:requirement]
              new_req_str = new_req[:requirement]

              base = "#{source_type}:#{dep.name}"
              old_specifier = prev_req_str ? "#{base}@#{prev_req_str}" : base
              new_specifier = "#{base}@#{new_req_str}"

              content = content.gsub(%r{#{Regexp.escape(old_specifier)}(?=["/])}, new_specifier)
            end
          end
          content
        end

        sig { returns(Dependabot::DependencyFile) }
        def manifest
          @manifest ||= T.let(
            T.must(dependency_files.find { |f| MANIFEST_FILENAMES.include?(f.name) }),
            T.nilable(Dependabot::DependencyFile)
          )
        end

        sig { returns(Dependabot::DependencyFile) }
        def lockfile
          @lockfile ||= T.let(
            T.must(dependency_files.find { |f| f.name == LOCKFILE_FILENAME }),
            T.nilable(Dependabot::DependencyFile)
          )
        end
      end
    end
  end
end
