# typed: strict
# frozen_string_literal: true

module Dependabot
  class DependencyGraph
    extend T::Sig

    sig { returns(T::Hash[String, DependencyNode]) }
    attr_reader :dependencies

    sig { returns(T::Hash[String, DependencyNode]) }
    attr_reader :all_dependencies

    sig { void }
    def initialize
      @dependencies = T.let({}, T::Hash[String, DependencyNode])
      @all_dependencies = T.let({}, T::Hash[String, DependencyNode])
    end

    sig do
      params(
        dependency: Dependency,
        dependency_data: T.nilable(T::Hash[String, T.untyped]),
        parent_key: T.nilable(String)
      ).returns(T.nilable(DependencyNode))
    end
    def add_dependency(dependency:, dependency_data:, parent_key: nil)
      parent = all_dependencies[parent_key] if parent_key
      key = dependency_key(dependency)

      return unless key

      node = all_dependencies[key] || DependencyNode.new(
        dependency: dependency,
        dependency_data: dependency_data
      )
      all_dependencies[key] = node

      # Add node to parent if it exists
      if parent
        parent.add_sub_dependency(node)
      # Add node to graph as main dependency if it has no parent
      else
        dependencies[key] = node
      end

      node
    end

    sig { params(name: String, version: T.nilable(String)).returns(T.nilable(DependencyNode)) }
    def find_dependency_by_name_and_version(name, version)
      key = if version
              "#{name}@#{version}"
            else
              name
            end
      all_dependencies[key]
    end

    sig { params(dependency: Dependency).returns(T.nilable(String)) }
    def dependency_key(dependency)
      dependency.version ? "#{dependency.name}@#{dependency.version}" : dependency.name
    end
  end

  class DependencyNode
    extend T::Sig

    sig { returns(Dependency) }
    attr_reader :dependency

    sig { returns(T.nilable(T::Hash[String, T.untyped])) }
    attr_reader :dependency_data

    sig { returns(T::Set[DependencyNode]) }
    attr_reader :children, :parents

    sig do
      params(
        dependency: Dependency,
        dependency_data: T.nilable(T::Hash[String, T.untyped])
      ).void
    end
    def initialize(dependency:, dependency_data:)
      @dependency = dependency
      @dependency_data = dependency_data
      @children = T.let(Set.new, T::Set[DependencyNode])
      @parents = T.let(Set.new, T::Set[DependencyNode])
    end

    sig { params(name: String).returns(T.nilable(DependencyNode)) }
    def child_by_name(name)
      children.find { |child| child.dependency.name == name }
    end

    protected

    sig { params(node: DependencyNode).void }
    def add_sub_dependency(node)
      children.add(node)
      node.parents.add(self)
    end

    sig { returns(Integer) }
    def hash
      [dependency.name, dependency.version].hash
    end

    sig { returns(T.nilable(String)) }
    def key
      dependency.version ? "#{dependency.name}@#{dependency.version}" : dependency.name
    end

    # Ensure equality is based on `key`
    sig { params(other: T.untyped).returns(T::Boolean) }
    def eql?(other)
      return false unless other.is_a?(DependencyNode)

      dependency.name == other.dependency.name && dependency.version == other.dependency.version
    end

    # Override `==` to use `key` comparison for general equality
    sig { params(other: T.untyped).returns(T::Boolean) }
    def ==(other)
      eql?(other)
    end
  end
end
