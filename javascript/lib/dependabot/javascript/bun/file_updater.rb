# typed: strict
# frozen_string_literal: true

module Dependabot
  module Javascript
    module Bun
      class FileUpdater < Shared::FileUpdater
        sig { override.returns(T::Array[Regexp]) }
        def self.updated_files_regex
          [
            %r{^(?:.*/)?package\.json$},
            %r{^(?:.*/)?bun\.lock$} # Matches bun.lock files
          ]
        end

        private

        sig { override.returns(T.class_of(FileParser::LockfileParser)) }
        def lockfile_parser_class
          FileParser::LockfileParser
        end

        sig { returns(T::Array[Dependabot::DependencyFile]) }
        def bun_locks
          @bun_locks ||= T.let(
            filtered_dependency_files
            .select { |f| f.name.end_with?("bun.lock") },
            T.nilable(T::Array[Dependabot::DependencyFile])
          )
        end

        sig { params(bun_lock: Dependabot::DependencyFile).returns(T::Boolean) }
        def bun_lock_changed?(bun_lock)
          bun_lock.content != updated_bun_lock_content(bun_lock)
        end

        sig { override.returns(T::Array[Dependabot::DependencyFile]) }
        def updated_lockfiles
          updated_files = []

          bun_locks.each do |bun_lock|
            next unless bun_lock_changed?(bun_lock)

            updated_files << updated_file(
              file: bun_lock,
              content: updated_bun_lock_content(bun_lock)
            )
          end

          updated_files
        end

        sig { params(bun_lock: Dependabot::DependencyFile).returns(String) }
        def updated_bun_lock_content(bun_lock)
          @updated_bun_lock_content ||= T.let({}, T.nilable(T::Hash[String, T.nilable(String)]))
          @updated_bun_lock_content[bun_lock.name] ||=
            bun_lockfile_updater.updated_bun_lock_content(bun_lock)
        end

        sig { returns(Bun::FileUpdater::LockfileUpdater) }
        def bun_lockfile_updater
          @bun_lockfile_updater ||= T.let(
            LockfileUpdater.new(
              dependencies: dependencies,
              dependency_files: dependency_files,
              repo_contents_path: repo_contents_path,
              credentials: credentials
            ),
            T.nilable(Bun::FileUpdater::LockfileUpdater)
          )
        end
      end
    end
  end
end
