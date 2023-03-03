# typed: strong
# frozen_string_literal: true

require "sorbet-runtime"

module Dependabot
  module Workspace
    class Base
      extend T::Sig
      extend T::Helpers
      extend T::Generic

      abstract!

      sig { returns(T::Array[Dependabot::Workspace::ChangeAttempt]) }
      attr_reader :change_attempts

      sig { returns(T.any(Pathname, String)) }
      attr_reader :path

      sig { params(path: T.any(Pathname, String)).void }
      def initialize(path)
        @path = path
        @change_attempts = T.let([], T::Array[Dependabot::Workspace::ChangeAttempt])
      end

      sig { returns(T::Boolean) }
      def changed?
        changes.any?
      end

      sig { returns(T::Array[Dependabot::Workspace::ChangeAttempt]) }
      def changes
        change_attempts.select(&:success?)
      end

      sig { returns(T::Array[Dependabot::Workspace::ChangeAttempt]) }
      def failed_change_attempts
        change_attempts.select(&:error?)
      end

      sig do
        type_parameters(:T)
          .params(
            memo: T.nilable(String),
            _blk: T.proc.params(arg0: T.any(Pathname, String)).returns(T.type_parameter(:T))
          )
          .returns(T.type_parameter(:T))
      end
      def change(memo = nil, &_blk)
        Dir.chdir(path) { yield(path) }
      rescue StandardError => e
        capture_failed_change_attempt(memo, e)
        clean # clean up any failed changes
        raise e
      end

      sig do
        abstract.params(memo: T.nilable(String)).returns(T.nilable(T::Array[Dependabot::Workspace::ChangeAttempt]))
      end
      def store_change(memo = nil); end

      sig { abstract.returns(String) }
      def to_patch; end

      sig { abstract.returns(NilClass) }
      def reset!; end

      protected

      sig do
        abstract
          .params(memo: T.nilable(String), error: T.nilable(StandardError))
          .returns(T.nilable(T::Array[Dependabot::Workspace::ChangeAttempt]))
      end
      def capture_failed_change_attempt(memo = nil, error = nil); end

      sig { abstract.returns(String) }
      def clean; end
    end
  end
end
