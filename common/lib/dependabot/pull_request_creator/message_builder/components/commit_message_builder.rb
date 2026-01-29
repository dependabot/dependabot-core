# typed: strong
# frozen_string_literal: true

require "sorbet-runtime"

module Dependabot
  class PullRequestCreator
    class MessageBuilder
      module Components
        # Builds commit messages with consistent structure:
        # - Subject line
        # - Body content
        # - Optional trailers (signed-off-by, etc.)
        class CommitMessageBuilder
          extend T::Sig

          sig do
            params(
              subject: String,
              body: String,
              trailers: T.nilable(String)
            ).void
          end
          def initialize(subject:, body:, trailers: nil)
            @subject = subject
            @body = body
            @trailers = trailers
          end

          sig { returns(String) }
          def build
            message = "#{@subject}\n\n"
            message += @body
            message += "\n\n#{@trailers}" if @trailers
            message
          end
        end
      end
    end
  end
end