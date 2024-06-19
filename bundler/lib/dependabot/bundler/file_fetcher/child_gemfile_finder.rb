# typed: strict
# frozen_string_literal: true

require "pathname"
require "parser/current"
require "dependabot/bundler/file_fetcher"
require "dependabot/errors"
require "sorbet-runtime"

module Dependabot
  module Bundler
    class FileFetcher
      # Finds the paths of any Gemfiles declared using `eval_gemfile` in the
      # passed Gemfile.
      class ChildGemfileFinder
        extend T::Sig

        sig { params(gemfile: Dependabot::DependencyFile).void }
        def initialize(gemfile:)
          @gemfile = gemfile
        end

        sig { returns(T::Array[String]) }
        def child_gemfile_paths
          ast = Parser::CurrentRuby.parse(gemfile&.content)
          find_child_gemfile_paths(ast)
        rescue Parser::SyntaxError
          raise Dependabot::DependencyFileNotParseable, T.must(gemfile&.path)
        end

        private

        sig { returns(T.nilable(Dependabot::DependencyFile)) }
        attr_reader :gemfile

        sig { params(node: T.untyped).returns(T::Array[String]) }
        def find_child_gemfile_paths(node)
          return [] unless node.is_a?(Parser::AST::Node)

          if declares_eval_gemfile?(node)
            path_node = node.children[2]
            unless path_node.type == :str
              path = gemfile&.path
              msg = "Dependabot only supports uninterpolated string arguments " \
                    "to eval_gemfile. Got " \
                    "`#{path_node.loc.expression.source}`"
              raise Dependabot::DependencyFileNotParseable.new(T.must(path), msg)
            end

            path = path_node.loc.expression.source.gsub(/['"]/, "")
            path = File.join(current_dir, path) unless current_dir.nil?
            return [Pathname.new(path).cleanpath.to_path]
          end

          node.children.flat_map do |child_node|
            find_child_gemfile_paths(child_node)
          end
        end

        sig { returns(T.nilable(String)) }
        def current_dir
          @current_dir ||= T.let(gemfile&.name&.rpartition("/")&.first, T.nilable(String))
          @current_dir = nil if @current_dir == ""
          @current_dir
        end

        sig { params(node: Parser::AST::Node).returns(T::Boolean) }
        def declares_eval_gemfile?(node)
          return false unless node.is_a?(Parser::AST::Node)

          node.children[1] == :eval_gemfile
        end
      end
    end
  end
end
