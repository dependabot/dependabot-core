# typed: strict
# frozen_string_literal: true

require "parser/current"
require "sorbet-runtime"

require "dependabot/bundler/file_updater"
require "dependabot/bundler/requirement"
require "dependabot/bundler/version"

module Dependabot
  module Bundler
    class FileUpdater
      class RubyRequirementSetter
        extend T::Sig

        RUBY_VERSIONS = %w(
          1.8.7 1.9.3 2.0.0 2.1.10 2.2.10 2.3.8 2.4.10 2.5.9 2.6.9 2.7.6 3.0.6 3.1.6 3.2.8 3.3.8 3.4.4
        ).freeze

        LANGUAGE = "ruby"

        sig { returns(Dependabot::DependencyFile) }
        attr_reader :gemspec

        sig { params(gemspec: Dependabot::DependencyFile).void }
        def initialize(gemspec:)
          @gemspec = gemspec
        end

        sig { params(content: String).returns(String) }
        def rewrite(content)
          return content unless gemspec_declares_ruby_requirement?

          buffer = Parser::Source::Buffer.new("(gemfile_content)")
          buffer.source = content
          ast = Parser::CurrentRuby.new.parse(buffer)

          if declares_ruby_version?(ast)
            GemfileRewriter.new(
              ruby_version: ruby_version
            ).rewrite(buffer, ast)
          else
            "ruby '#{ruby_version}'\n" + content
          end
        end

        private

        sig { returns(T::Boolean) }
        def gemspec_declares_ruby_requirement?
          !ruby_requirement.nil?
        end

        sig { params(node: T.untyped).returns(T::Boolean) }
        def declares_ruby_version?(node)
          return false unless node.is_a?(Parser::AST::Node)
          return true if node.type == :send && node.children[1] == :ruby

          node.children.any? { |cn| declares_ruby_version?(cn) }
        end

        sig { returns(Dependabot::Version) }
        def ruby_version
          requirement = if ruby_requirement.is_a?(Gem::Requirement)
                          ruby_requirement
                        else
                          Dependabot::Bundler::Requirement.new(ruby_requirement)
                        end

          ruby_version =
            RUBY_VERSIONS
            .map { |v| Dependabot::Bundler::Version.new(v) }.sort
            .find { |v| requirement.satisfied_by?(v) }

          unless ruby_version
            raise ToolVersionNotSupported.new(
              LANGUAGE,
              requirement.to_s,
              RUBY_VERSIONS.join(", ")
            )
          end

          ruby_version
        end

        # rubocop:disable Security/Eval
        sig { returns(T.untyped) }
        def ruby_requirement
          ast = Parser::CurrentRuby.parse(gemspec.content)
          requirement_node = find_ruby_requirement_node(ast)
          return unless requirement_node

          begin
            eval(requirement_node.children[2].loc.expression.source)
          rescue StandardError
            nil # If we can't evaluate the expression just return nil
          end
        end
        # rubocop:enable Security/Eval

        sig { params(node: T.untyped).returns(T.nilable(Parser::AST::Node)) }
        def find_ruby_requirement_node(node)
          return unless node.is_a?(Parser::AST::Node)
          return node if declares_ruby_requirement?(node)

          node.children.find do |cn|
            requirement_node = find_ruby_requirement_node(cn)
            break requirement_node if requirement_node
          end
        end

        sig { params(node: T.untyped).returns(T::Boolean) }
        def declares_ruby_requirement?(node)
          return false unless node.is_a?(Parser::AST::Node)

          node.children[1] == :required_ruby_version=
        end

        class GemfileRewriter < Parser::TreeRewriter
          extend T::Sig

          sig { override.params(ruby_version: Dependabot::Version).void }
          def initialize(ruby_version:)
            @ruby_version = ruby_version
          end

          sig { override.params(node: T.untyped).void }
          def on_send(node)
            return unless declares_ruby_version?(node)

            assigned_version_node = node.children[2]
            replace(assigned_version_node.loc.expression, "'#{ruby_version}'")
          end

          private

          sig { returns(Dependabot::Version) }
          attr_reader :ruby_version

          sig { params(node: T.untyped).returns(T::Boolean) }
          def declares_ruby_version?(node)
            return false unless node.is_a?(Parser::AST::Node)
            return false unless node.type == :send

            node.children[1] == :ruby
          end
        end
      end
    end
  end
end
