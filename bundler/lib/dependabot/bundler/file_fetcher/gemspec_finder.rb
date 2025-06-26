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
          result = Prism.parse(T.must(gemfile).content)
          raise Dependabot::DependencyFileNotParseable, T.must(gemfile).path if result.failure?

          find_gemspec_paths(result.value)
        end

        private

        sig { returns(T.nilable(Dependabot::DependencyFile)) }
        attr_reader :gemfile

        sig { params(node: T.nilable(Prism::Node)).returns(T::Array[T.untyped]) }
        def find_gemspec_paths(node)
          return [] if node.nil?

          if declares_gemspec_dependency?(node)
            path_node = path_node_for_gem_declaration(node)
            return [clean_path(".")] unless path_node

            unless path_node.is_a?(Prism::StringNode)
              path = T.must(gemfile).path
              msg = "Dependabot only supports uninterpolated string arguments " \
                    "to gemspec. Got " \
                    "`#{path_node.slice}`"
              raise Dependabot::DependencyFileNotParseable.new(path, msg)
            end

            path = path_node.unescaped
            return [clean_path(path)]
          end

          node.child_nodes.flat_map do |child_node|
            find_gemspec_paths(child_node)
          end
        end

        sig { returns(T.nilable(String)) }
        def current_dir
          @current_dir ||= T.let(gemfile&.name&.rpartition("/")&.first, T.nilable(String))
          @current_dir = nil if @current_dir == ""
          @current_dir
        end

        sig { params(node: Prism::Node).returns(T::Boolean) }
        def declares_gemspec_dependency?(node)
          return false unless node.is_a?(Prism::CallNode)

          node.name == :gemspec
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
