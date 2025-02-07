# typed: strong
# frozen_string_literal: true

module Dependabot
  module Javascript
    module Bun
      class UpdateChecker
        class DependencyFilesBuilder < Dependabot::Javascript::UpdateChecker::DependencyFilesBuilder
          extend T::Sig

          sig { returns(T::Array[Dependabot::DependencyFile]) }
          def bun_locks
            @bun_locks ||= T.let(
              dependency_files
              .select { |f| f.name.end_with?("bun.lock") },
              T.nilable(T::Array[Dependabot::DependencyFile])
            )
          end

          sig { returns(T.nilable(Dependabot::DependencyFile)) }
          def root_bun_lock
            @root_bun_lock ||= T.let(
              dependency_files
              .find { |f| f.name == "bun.lock" },
              T.nilable(Dependabot::DependencyFile)
            )
          end

          sig { override.returns(T::Array[Dependabot::DependencyFile]) }
          def lockfiles
            [*bun_locks]
          end

          private

          sig { override.returns(T::Array[Dependabot::DependencyFile]) }
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
end
