# typed: strict
# frozen_string_literal: true

require "parser/current"
require "sorbet-runtime"

require "dependabot/bundler/file_updater"

module Dependabot
  module Bundler
    class FileUpdater
      class GitSourceRemover
        extend T::Sig

        sig { returns(Dependabot::Dependency) }
        attr_reader :dependency

        sig { params(dependency: Dependabot::Dependency).void }
        def initialize(dependency:)
          @dependency = dependency
        end

        sig { params(content: String).returns(String) }
        def rewrite(content)
          buffer = Parser::Source::Buffer.new("(gemfile_content)")
          buffer.source = content
          ast = Parser::CurrentRuby.new.parse(buffer)

          Rewriter.new(dependency: dependency).rewrite(buffer, ast)
        end

        class Rewriter < Parser::TreeRewriter
          extend T::Sig

          # TODO: Hack until Bundler 1.16.0 is available on Heroku
          GOOD_KEYS = %i(
            group groups path glob name require platform platforms type
            source install_if
          ).freeze

          sig { returns(Dependabot::Dependency) }
          attr_reader :dependency

          sig { params(dependency: Dependabot::Dependency).void }
          def initialize(dependency:)
            @dependency = T.let(dependency, Dependabot::Dependency)
          end

          sig { params(node: Parser::AST::Node).void }
          def on_send(node)
            return unless declares_targeted_gem?(node)
            return unless node.children.last.type == :hash

            kwargs_node = node.children.last
            keys = kwargs_node.children.map do |hash_pair|
              key_from_hash_pair(hash_pair)
            end

            if keys.none? { |key| GOOD_KEYS.include?(key) }
              remove_all_kwargs(node)
            else
              remove_git_related_kwargs(kwargs_node)
            end
          end

          private

          sig { params(node: Parser::AST::Node).returns(T::Boolean) }
          def declares_targeted_gem?(node)
            return false unless node.children[1] == :gem

            node.children[2].children.first == dependency.name
          end

          sig { params(node: Parser::AST::Node).returns(Symbol) }
          def key_from_hash_pair(node)
            node.children.first.children.first.to_sym
          end

          sig { params(node: Parser::AST::Node).void }
          def remove_all_kwargs(node)
            kwargs_node = node.children.last

            range_to_remove =
              kwargs_node.loc.expression.join(node.children[-2].loc.end.end)

            remove(range_to_remove)
          end

          sig { params(kwargs_node: Parser::AST::Node).void }
          def remove_git_related_kwargs(kwargs_node)
            good_key_index = T.let(nil, T.nilable(Integer))
            hash_pairs = kwargs_node.children

            hash_pairs.each_with_index do |hash_pair, index|
              if GOOD_KEYS.include?(key_from_hash_pair(hash_pair))
                good_key_index = index
                next
              end

              range_to_remove =
                if good_key_index.nil?
                  next_arg_start = hash_pairs[index + 1].loc.expression.begin
                  hash_pair.loc.expression.join(next_arg_start)
                else
                  last_arg_end = hash_pairs[good_key_index].loc.expression.end
                  hash_pair.loc.expression.join(last_arg_end)
                end

              remove(range_to_remove)
            end
          end
        end
      end
    end
  end
end
