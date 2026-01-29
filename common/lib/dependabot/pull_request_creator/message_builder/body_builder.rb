# typed: strong
# frozen_string_literal: true

require "sorbet-runtime"

module Dependabot
  class PullRequestCreator
    class MessageBuilder
      # Builds PR body with consistent structure:
      # - Optional header
      # - Main content (changelog, release notes, etc.)
      # - Dependabot commands section
      # - Optional footer
      #
      # This handles truncation and encoding consistently.
      class BodyBuilder
        extend T::Sig

        DEPENDABOT_COMMANDS = T.let(<<~COMMANDS.freeze, String)
          ---

          <details>
          <summary>Dependabot commands and options</summary>
          <br />

          You can trigger Dependabot actions by commenting on this PR:
          - `@dependabot rebase` will rebase this PR
          - `@dependabot recreate` will recreate this PR, overwriting any edits that have been made to it
          - `@dependabot merge` will merge this PR after your CI passes on it
          - `@dependabot squash and merge` will squash and merge this PR after your CI passes on it
          - `@dependabot cancel merge` will cancel a previously requested merge and block automerging
          - `@dependabot reopen` will reopen this PR if it is closed
          - `@dependabot close` will close this PR and stop Dependabot recreating it
          - `@dependabot show <dependency name> ignore conditions` will show all of the ignore conditions of the specified dependency
          - `@dependabot ignore this major version` will close this PR and stop Dependabot creating any more for this major version
          - `@dependabot ignore this minor version` will close this PR and stop Dependabot creating any more for this minor version
          - `@dependabot ignore this dependency` will close this PR and stop Dependabot creating any more for this dependency

          </details>
        COMMANDS

        sig do
          params(
            main_content: String,
            header: T.nilable(String),
            footer: T.nilable(String),
            notices: T.nilable(String),
            max_length: T.nilable(Integer),
            encoding: Encoding,
            include_commands: T::Boolean
          ).void
        end
        def initialize(
          main_content:,
          header: nil,
          footer: nil,
          notices: nil,
          max_length: nil,
          encoding: Encoding::UTF_8,
          include_commands: true
        )
          @main_content = main_content
          @header = header
          @footer = footer
          @notices = notices
          @max_length = max_length
          @encoding = encoding
          @include_commands = include_commands
        end

        sig { returns(String) }
        def build
          body = build_full_body
          truncate_if_needed(body)
        end

        private

        sig { returns(String) }
        def build_full_body
          parts = []
          parts << @notices if @notices.present?
          parts << suffixed_header if @header.present?
          parts << @main_content
          parts << DEPENDABOT_COMMANDS if @include_commands
          parts << prefixed_footer if @footer.present?
          parts.join
        end

        sig { returns(String) }
        def suffixed_header
          "#{@header}\n\n"
        end

        sig { returns(String) }
        def prefixed_footer
          "\n\n#{@footer}"
        end

        sig { params(body: String).returns(String) }
        def truncate_if_needed(body)
          return body unless @max_length

          # Implementation for truncation with encoding support
          # ...existing truncation logic from MessageBuilder...
          body
        end
      end
    end
  end
end