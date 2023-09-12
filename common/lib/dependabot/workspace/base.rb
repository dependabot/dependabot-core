# typed: false
# frozen_string_literal: true

module Dependabot
  module Workspace
    class Base
      attr_reader :change_attempts, :path

      def initialize(path)
        @path = path
        @change_attempts = []
      end

      def changed?
        changes.any?
      end

      def changes
        change_attempts.select(&:success?)
      end

      def failed_change_attempts
        change_attempts.select(&:error?)
      end

      def change(memo = nil)
        Dir.chdir(path) { yield(path) }
      rescue StandardError => e
        capture_failed_change_attempt(memo, e)
        clean # clean up any failed changes
        raise e
      end

      def store_change(memo = nil); end

      def to_patch
        ""
      end

      def reset!; end

      protected

      def capture_failed_change_attempt(memo = nil, error = nil); end
    end
  end
end
