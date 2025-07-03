# typed: strict
# frozen_string_literal: true

require "pathname"
require "prism"
require "dependabot/bundler/file_fetcher"
require "dependabot/errors"
require "sorbet-runtime"

module Dependabot
  module Bundler
    class FileFetcher
      # Finds the paths of any gemspecs declared using `path: ` in the
      # passed Gemfile.
      class PathGemspecFinder
        extend T::Sig

        sig { params(gemfile: Dependabot::DependencyFile).void }
        def initialize(gemfile:)
          @gemfile = gemfile
        end

        sig { returns(T::Array[String]) }
        def path_gemspec_paths
          result = Prism.parse(gemfile&.content)
          raise Dependabot::DependencyFileNotParseable, T.must(gemfile).path if result.failure?

          find_path_gemspec_paths(result.value)
        end

        private

        sig { returns(T.nilable(Dependabot::DependencyFile)) }
        attr_reader :gemfile

        sig { params(node: T.untyped).returns(T::Array[T.untyped]) }
        def find_path_gemspec_paths(node)
          return [] unless node.is_a?(Prism::Node)

          if declares_path_dependency?(node)
            path_node = path_node_for_gem_declaration(node)

            unless path_node.is_a?(Prism::StringNode)
              path = gemfile&.path
              msg = "Dependabot only supports uninterpolated string arguments " \
                    "for path dependencies. Got " \
                    "`#{path_node&.slice}`"
              raise Dependabot::DependencyFileNotParseable.new(T.must(path), msg)
            end

            path = path_node.unescaped
            return [clean_path(path)]
          end

          node.child_nodes.flat_map do |child_node|
            find_path_gemspec_paths(child_node)
          end
        end

        sig { returns(T.nilable(String)) }
        def current_dir
          @current_dir ||= T.let(gemfile&.name&.rpartition("/")&.first, T.nilable(String))
          @current_dir = nil if @current_dir == ""
          @current_dir
        end

        sig { params(node: Prism::Node).returns(T::Boolean) }
        def declares_path_dependency?(node)
          return false unless node.is_a?(Prism::CallNode)
          return false unless node.name == :gem

          !path_node_for_gem_declaration(node).nil?
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

        sig { params(node: Prism::Node).returns(T.nilable(Prism::Node)) }
        def path_node_for_gem_declaration(node)
          return unless node.is_a?(Prism::CallNode)

          kwargs_node = node.arguments&.arguments&.last

          return unless kwargs_node.is_a?(Prism::Node)

          path_hash_pair =
            kwargs_node.child_nodes
                       .find { |hash_pair| key_from_hash_pair(hash_pair) == :path }

          return unless path_hash_pair

          T.cast(path_hash_pair, Prism::AssocNode).value
        end

        sig { params(node: T.nilable(Prism::Node)).returns(T.nilable(Symbol)) }
        def key_from_hash_pair(node)
          return unless node.is_a?(Prism::AssocNode)

          key_node = node.key
          return unless key_node.is_a?(Prism::StringNode) || key_node.is_a?(Prism::SymbolNode)

          key_node.unescaped.to_sym
        end
      end
    end
  end
end
