# typed: strong
# frozen_string_literal: true

require "dependabot/github_actions/file_updater/workflow_updater"

module Dependabot
  module GithubActions
    class FileUpdater < Dependabot::FileUpdaters::Base
      class WorkflowUpdater
        class YamlCommentFinder
          extend T::Sig

          sig { params(suffix: String).returns(T.nilable(String)) }
          def find(suffix)
            previous_non_whitespace = T.let(nil, T.nilable(String))
            index = 0

            while index < suffix.length
              character = T.must(suffix[index])
              if quoted_scalar_start?(character, previous_non_whitespace)
                previous_non_whitespace = character
                index = quoted_scalar_end(suffix, index)
                next
              end

              return comment_with_leading_whitespace(suffix, index) if comment_start?(suffix, index)

              previous_non_whitespace = character unless character.match?(/\s/)
              index += 1
            end
            nil
          end

          private

          sig { params(character: String, previous_non_whitespace: T.nilable(String)).returns(T::Boolean) }
          def quoted_scalar_start?(character, previous_non_whitespace)
            return false unless character == "'" || character == '"'

            previous_non_whitespace.nil? || ":,[{?-".include?(previous_non_whitespace)
          end

          sig { params(suffix: String, quote_index: Integer).returns(Integer) }
          def quoted_scalar_end(suffix, quote_index)
            quote = T.must(suffix[quote_index])
            index = quote_index + 1

            while index < suffix.length
              character = T.must(suffix[index])
              if quote == "'" && character == "'" && suffix[index + 1] == "'"
                index += 2
              elsif quote == '"' && character == "\\"
                index += 2
              elsif character == quote
                return index + 1
              else
                index += 1
              end
            end
            suffix.length
          end

          sig { params(suffix: String, index: Integer).returns(T::Boolean) }
          def comment_start?(suffix, index)
            suffix[index] == "#" && index.positive? && T.must(suffix[index - 1]).match?(/\s/)
          end

          sig { params(suffix: String, hash_index: Integer).returns(String) }
          def comment_with_leading_whitespace(suffix, hash_index)
            comment_start = hash_index
            comment_start -= 1 while comment_start.positive? && T.must(suffix[comment_start - 1]).match?(/\s/)
            T.must(suffix[comment_start..])
          end
        end
      end
    end
  end
end
