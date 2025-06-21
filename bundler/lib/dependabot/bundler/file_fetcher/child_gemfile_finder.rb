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
          result = Prism.parse(gemfile&.content)
          raise Dependabot::DependencyFileNotParseable, T.must(gemfile&.path) if result.failure?

          find_child_gemfile_paths(result.value)
        end

        private

        sig { returns(T.nilable(Dependabot::DependencyFile)) }
        attr_reader :gemfile

        sig { params(node: T.untyped).returns(T::Array[String]) }
        def find_child_gemfile_paths(node)
          return [] if node.nil?

          if declares_eval_gemfile?(node)
            path_node = node.arguments&.arguments&.first
            unless path_node.is_a?(Prism::StringNode)
              path = gemfile&.path
              msg = "Dependabot only supports uninterpolated string arguments " \
                    "to eval_gemfile. Got " \
                    "`#{path_node.slice}`"
              raise Dependabot::DependencyFileNotParseable.new(T.must(path), msg)
            end

            path = path_node.unescaped
            path = File.join(current_dir, path) unless current_dir.nil?
            return [Pathname.new(path).cleanpath.to_path]
          end

          node.child_nodes.flat_map do |child_node|
            find_child_gemfile_paths(child_node)
          end
        end

        sig { returns(T.nilable(String)) }
        def current_dir
          @current_dir ||= T.let(gemfile&.name&.rpartition("/")&.first, T.nilable(String))
          @current_dir = nil if @current_dir == ""
          @current_dir
        end

        sig { params(node: Prism::Node).returns(T::Boolean) }
        def declares_eval_gemfile?(node)
          return false unless node.is_a?(Prism::CallNode)

          node.name == :eval_gemfile
        end
      end
    end
  end
end
