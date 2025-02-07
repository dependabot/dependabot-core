# typed: strong
# frozen_string_literal: true

module Dependabot
  module Bun
    class UpdateChecker
      class DependencyFilesBuilder < Javascript::UpdateChecker::DependencyFilesBuilder
        extend T::Sig

        sig { returns(T::Array[DependencyFile]) }
        def bun_locks
          @bun_locks ||= T.let(
            dependency_files
            .select { |f| f.name.end_with?("bun.lock") },
            T.nilable(T::Array[DependencyFile])
          )
        end

        sig { returns(T.nilable(DependencyFile)) }
        def root_bun_lock
          @root_bun_lock ||= T.let(
            dependency_files
            .find { |f| f.name == "bun.lock" },
            T.nilable(DependencyFile)
          )
        end

        sig { override.returns(T::Array[DependencyFile]) }
        def lockfiles
          [*bun_locks]
        end

        private

        sig { override.returns(T::Array[DependencyFile]) }
        def write_lockfiles
          [*bun_locks].each do |f|
            FileUtils.mkdir_p(Pathname.new(f.name).dirname)
            File.write(f.name, f.content)
          end
        end
      end
    end
  end
end
