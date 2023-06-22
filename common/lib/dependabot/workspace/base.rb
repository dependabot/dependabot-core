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
        change_attempt = nil
        Dir.chdir(path) { yield(path) }
        change_attempt = capture_change(memo)
      rescue StandardError => e
        change_attempt = capture_failed_change_attempt(memo, e)
        raise e
      ensure
        change_attempts << change_attempt unless change_attempt.nil?
        clean
      end

      def to_patch
        ""
      end

      def reset!; end

      protected

      def capture_change(memo = nil); end

      def capture_failed_change_attempt(memo = nil, error = nil); end
    end
  end
end
