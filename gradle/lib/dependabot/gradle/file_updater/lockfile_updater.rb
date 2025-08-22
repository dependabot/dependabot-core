# typed: strong
# frozen_string_literal: true

require "sorbet-runtime"
require "shellwords"

require "dependabot/gradle/file_updater/gradle_updater_base"

module Dependabot
  module Gradle
    class FileUpdater
      class LockfileUpdater < GradleUpdaterBase
        extend T::Sig

        sig { override.params(file: Dependabot::DependencyFile).returns(T::Boolean) }
        def target_file?(file)
          file.name.end_with?(".lockfile")
        end

        sig { override.returns(T::Array[String]) }
        def command_args
          %w(dependencies --write-locks)
        end
      end
    end
  end
end
