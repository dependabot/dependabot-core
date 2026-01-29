# typed: strong
# frozen_string_literal: true

require "sorbet-runtime"

module Dependabot
  class PullRequestCreator
    class MessageBuilder
      module Components
        # Builds PR body with consistent structure:
        # - Optional notices
        # - Optional header
        # - Main content (changelog, release notes, etc.)
        # - Optional footer
        #
        # Handles truncation and encoding consistently.
        class BodyBuilder
          extend T::Sig

          TRUNCATED_MSG = T.let("...\n\n_Description has been truncated_".freeze, String)

          sig do
            params(
              main_content: String,
              header: T.nilable(String),
              footer: T.nilable(String),
              notices: T.nilable(String),
              max_length: T.nilable(Integer),
              encoding: T.nilable(Encoding)
            ).void
          end
          def initialize(
            main_content:,
            header: nil,
            footer: nil,
            notices: nil,
            max_length: nil,
            encoding: nil
          )
            @main_content = main_content
            @header = header
            @footer = footer
            @notices = notices
            @max_length = max_length
            @encoding = encoding
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
            parts << @notices if @notices&.present?
            parts << "#{@header}\n\n" if @header&.present?
            parts << @main_content
            parts << "\n\n#{@footer}" if @footer&.present?
            parts.join
          end

          sig { params(body: String).returns(String) }
          def truncate_if_needed(body)
            return body if @max_length.nil?

            encoded_body = body.dup
            encoded_body = encoded_body.force_encoding(T.must(@encoding)) unless @encoding.nil?

            if encoded_body.length > T.must(@max_length)
              truncated_msg = @encoding.nil? ? TRUNCATED_MSG : TRUNCATED_MSG.dup.force_encoding(T.must(@encoding))
              trunc_length = T.must(@max_length) - truncated_msg.length
              encoded_body = T.must(encoded_body[0..trunc_length]) + truncated_msg
            end

            encoded_body = encoded_body.encode("utf-8", "binary", invalid: :replace, undef: :replace) unless @encoding.nil?
            encoded_body
          end
        end
      end
    end
  end
end