# typed: strict
# frozen_string_literal: true

module Dependabot
  module Bun
    class FileParser
      class LockfileParser < Dependabot::Javascript::FileParser::LockfileParser
        extend T::Sig

        sig { override.returns(Dependabot::FileParsers::Base::DependencySet) }
        def parse_set
          dependency_set = Dependabot::FileParsers::Base::DependencySet.new

          bun_locks.each do |file|
            dependency_set += lockfile_for(file).dependencies
          end

          dependency_set
        end

        private

        sig { override.params(file: DependencyFile).returns(BunLock) }
        def lockfile_for(file)
          @lockfiles ||= T.let({}, T.nilable(T::Hash[String, BunLock]))
          @lockfiles[file.name] ||= case file.name
                                    when *bun_locks.map(&:name)
                                      Bun::FileParser::BunLock.new(file)
                                    else
                                      raise "Unexpected lockfile: #{file.name}"
                                    end
        end

        sig { returns(T::Array[DependencyFile]) }
        def bun_locks
          @bun_locks ||= T.let(select_files_by_extension("bun.lock"), T.nilable(T::Array[DependencyFile]))
        end

        sig { override.returns(T.class_of(Version)) }
        def version_class
          Version
        end
      end
    end
  end
end
