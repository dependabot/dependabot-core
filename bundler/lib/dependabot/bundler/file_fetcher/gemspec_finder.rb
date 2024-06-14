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
      # Finds the directories of any gemspecs declared using `gemspec` in the
      # passed Gemfile.
      class GemspecFinder
        extend T::Sig

        sig { params(gemfile: Dependabot::DependencyFile).void }
        def initialize(gemfile:)
          @gemfile = gemfile
        end

        sig { returns(T::Array[String]) }
        def gemspec_directories
          ast = Parser::CurrentRuby.parse(T.must(gemfile).content)
          find_gemspec_paths(ast)
        rescue Parser::SyntaxError
          raise Dependabot::DependencyFileNotParseable, T.must(gemfile).path
        end

        private

        sig { returns(T.nilable(Dependabot::DependencyFile)) }
        attr_reader :gemfile

        sig { params(node: T.untyped).returns(T::Array[T.untyped]) }
        def find_gemspec_paths(node)
          return [] unless node.is_a?(Parser::AST::Node)

          if declares_gemspec_dependency?(node)
            path_node = path_node_for_gem_declaration(node)
            return [clean_path(".")] unless path_node

            unless path_node.type == :str
              path = T.must(gemfile).path
              msg = "Dependabot only supports uninterpolated string arguments " \
                    "to gemspec. Got " \
                    "`#{path_node.loc.expression.source}`"
              raise Dependabot::DependencyFileNotParseable.new(path, msg)
            end

            path = path_node.loc.expression.source.gsub(/['"]/, "")
            return [clean_path(path)]
          end

          node.children.flat_map do |child_node|
            find_gemspec_paths(child_node)
          end
        end

        sig { returns(T.nilable(String)) }
        def current_dir
          @current_dir ||= T.let(T.must(gemfile).name.rpartition("/").first, T.nilable(String))
          @current_dir = nil if @current_dir == ""
          @current_dir
        end

        sig { params(node: Parser::AST::Node).returns(T::Boolean) }
        def declares_gemspec_dependency?(node)
          return false unless node.is_a?(Parser::AST::Node)

          node.children[1] == :gemspec
        end

        sig { params(path: String).returns(Pathname) }
        def clean_path(path)
          if Pathname.new(path).absolute?
            base_path = Pathname.new(File.expand_path(Dir.pwd))
            path = Pathname.new(path).relative_path_from(base_path).to_s
          end
          path = File.join(current_dir, path) unless current_dir.nil?
          Pathname.new(path).cleanpath
        end

        sig { params(node: Parser::AST::Node).returns(T.nilable(Parser::AST::Node)) }
        def path_node_for_gem_declaration(node)
          return unless node.children.last.is_a?(Parser::AST::Node)
          return unless node.children.last.type == :hash

          kwargs_node = node.children.last

          path_hash_pair =
            kwargs_node.children
                       .find { |hash_pair| key_from_hash_pair(hash_pair) == :path }

          return unless path_hash_pair

          path_hash_pair.children.last
        end

        sig { params(node: Parser::AST::Node).returns(Symbol) }
        def key_from_hash_pair(node)
          node.children.first.children.first.to_sym
        end
      end
    end
  end
end
