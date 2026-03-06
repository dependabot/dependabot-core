# typed: strong
# frozen_string_literal: true

require "dependabot/python/update_checker/pip_version_resolver"

module Dependabot
  module Python
    class UpdateChecker
      class PipVersionResolver
        class MarkerEvaluator
          extend T::Sig

          sig { params(requirement_string: String).returns([T.nilable(String), T.nilable(String)]) }
          def split_requirement_and_marker(requirement_string)
            separator_index = T.let(nil, T.nilable(Integer))
            in_single_quote = T.let(false, T::Boolean)
            in_double_quote = T.let(false, T::Boolean)

            requirement_string.each_char.with_index do |char, index|
              in_single_quote, in_double_quote, quote_toggled =
                toggle_quote_state(char, in_single_quote, in_double_quote)
              next if quote_toggled
              next if in_single_quote || in_double_quote
              next unless char == ";"

              separator_index = index
              break
            end

            return [requirement_string.strip, nil] if separator_index.nil?

            requirement_part = requirement_string[0...separator_index]
            marker_part = requirement_string[(separator_index + 1)..]

            [requirement_part&.strip, marker_part&.strip]
          end

          sig { params(marker: String, python_version: String).returns(T::Boolean) }
          def marker_satisfied?(marker:, python_version:)
            evaluate_marker_expression(marker, python_version)
          rescue ArgumentError
            # If we cannot safely parse a python marker, treat it as applicable.
            # This avoids silently skipping transitive constraints that may break installs.
            true
          end

          private

          sig { params(expression: String, python_version: String).returns(T::Boolean) }
          def evaluate_marker_expression(expression, python_version)
            expr = strip_wrapping_parentheses(expression.strip)

            not_expression = strip_top_level_not(expr)
            if not_expression
              return false unless python_marker?(not_expression)

              return !evaluate_marker_expression(not_expression, python_version)
            end

            or_parts = split_top_level(expr, "or")
            return or_parts.any? { |part| evaluate_marker_expression(part, python_version) } if or_parts.length > 1

            and_parts = split_top_level(expr, "and")
            if and_parts.length > 1
              return and_parts.all? do |part|
                evaluate_marker_expression(part, python_version) || !python_marker?(part)
              end
            end

            evaluate_python_version_condition(expr, python_version, default: python_marker?(expr))
          end

          sig { params(expression: String).returns(T.nilable(String)) }
          def strip_top_level_not(expression)
            return nil unless expression.start_with?("not")
            return nil unless word_at?(expression, 0, "not")

            remaining = expression[3..]&.strip
            return nil if remaining.nil? || remaining.empty?

            remaining
          end

          sig { params(expression: String).returns(T::Boolean) }
          def python_marker?(expression)
            expression.match?(/\bpython(?:_full)?_version\b/)
          end

          sig { params(expression: String).returns(String) }
          def strip_wrapping_parentheses(expression)
            expr = expression
            while expr.start_with?("(") && expr.end_with?(")")
              inner = expr[1...-1].to_s.strip
              break unless balanced_parentheses?(inner)

              expr = inner
            end

            expr
          end

          sig { params(expression: String).returns(T::Boolean) }
          def balanced_parentheses?(expression)
            depth = T.let(0, Integer)
            in_single_quote = T.let(false, T::Boolean)
            in_double_quote = T.let(false, T::Boolean)

            expression.each_char do |char|
              in_single_quote, in_double_quote, quote_toggled =
                toggle_quote_state(char, in_single_quote, in_double_quote)
              next if quote_toggled
              next if in_single_quote || in_double_quote

              depth += 1 if char == "("
              depth -= 1 if char == ")"
              return false if depth.negative?
            end

            depth.zero? && !in_single_quote && !in_double_quote
          end

          sig do
            params(
              char: String,
              in_single_quote: T::Boolean,
              in_double_quote: T::Boolean
            ).returns([T::Boolean, T::Boolean, T::Boolean])
          end
          def toggle_quote_state(char, in_single_quote, in_double_quote)
            return [!in_single_quote, in_double_quote, true] if char == "'" && !in_double_quote

            return [in_single_quote, !in_double_quote, true] if char == '"' && !in_single_quote

            [in_single_quote, in_double_quote, false]
          end

          sig { params(expression: String, operator: String).returns(T::Array[String]) }
          def split_top_level(expression, operator)
            parts = T.let([], T::Array[String])
            token = T.let(+"", String)
            depth = T.let(0, Integer)
            in_single_quote = T.let(false, T::Boolean)
            in_double_quote = T.let(false, T::Boolean)
            i = T.let(0, Integer)

            while i < expression.length
              char = T.must(expression[i])

              in_single_quote, in_double_quote, quote_toggled =
                toggle_quote_state(char, in_single_quote, in_double_quote)
              if quote_toggled
                token << char
                i += 1
                next
              end

              depth = update_depth_for_unquoted_char(char, depth, in_single_quote, in_double_quote)

              if depth.zero? && !in_single_quote && !in_double_quote && word_at?(expression, i, operator)
                parts << token.strip
                token = +""
                i += operator.length
                next
              end

              token << char
              i += 1
            end

            parts << token.strip
            parts
          end

          sig do
            params(
              char: String,
              depth: Integer,
              in_single_quote: T::Boolean,
              in_double_quote: T::Boolean
            ).returns(Integer)
          end
          def update_depth_for_unquoted_char(char, depth, in_single_quote, in_double_quote)
            return depth if in_single_quote || in_double_quote

            depth += 1 if char == "("
            depth -= 1 if char == ")"
            depth
          end

          sig { params(expression: String, index: Integer, word: String).returns(T::Boolean) }
          def word_at?(expression, index, word)
            return false unless expression[index, word.length] == word

            before = index.zero? ? " " : T.must(expression[index - 1])
            after_index = index + word.length
            after = after_index >= expression.length ? " " : T.must(expression[after_index])

            word_boundary?(before) && word_boundary?(after)
          end

          sig { params(char: String).returns(T::Boolean) }
          def word_boundary?(char)
            !!(char =~ /[^A-Za-z0-9_]/)
          end

          sig do
            params(
              condition: T.nilable(String),
              python_version: String,
              default: T::Boolean
            ).returns(T::Boolean)
          end
          def evaluate_python_version_condition(condition, python_version, default:)
            return default if condition.nil?

            candidate = strip_wrapping_parentheses(condition.strip)
            match = candidate.match(/\Apython(?:_full)?_version\s*(<=|>=|<|>|==|!=)\s*['\"]([^'\"]+)['\"]\z/)
            return default unless match

            operator = T.must(match[1])
            version = T.must(match[2])
            lhs = Dependabot::Python::Version.new(python_version)
            rhs = Dependabot::Python::Version.new(version)

            case operator
            when "<" then lhs < rhs
            when "<=" then lhs <= rhs
            when ">" then lhs > rhs
            when ">=" then lhs >= rhs
            when "==" then lhs == rhs
            when "!=" then lhs != rhs
            else false
            end
          rescue ArgumentError
            true
          end
        end
      end
    end
  end
end
