# typed: strong
# frozen_string_literal: true

require "pathname"
require "shellwords"
require "sorbet-runtime"

require "dependabot/dependency_file"

module Dependabot
  module Python
    module RequirementReferences
      extend T::Sig

      CHILD_REQUIREMENT_REGEX = /^-r\s?(?<path>.*\.(?:txt|in))/
      CONSTRAINT_REGEX = /^-c\s?(?<path>.*\.(?:txt|in))/
      COMMENT_PATTERN = /(^|\s+)#.*$/
      REQUIREMENT_FILE_EXTENSIONS = %w(.txt .in).freeze
      SEPARATED_REFERENCE_OPTIONS = T.let(
        {
          "-r" => false,
          "--requirement" => false,
          "-c" => true,
          "--constraint" => true
        }.freeze,
        T::Hash[String, T::Boolean]
      )
      ParsedReferenceOption = T.type_alias { [T.nilable(String), T::Boolean, Integer] }

      class Reference < T::Struct
        const :path, String
        const :constraint, T::Boolean
      end

      sig { params(file: Dependabot::DependencyFile).returns(T::Array[String]) }
      def self.paths(file)
        references(file).map(&:path).uniq
      end

      sig { params(file: Dependabot::DependencyFile).returns(T::Array[String]) }
      def self.requirement_paths(file)
        references(file).reject(&:constraint).map(&:path).uniq
      end

      sig { params(file: Dependabot::DependencyFile).returns(T::Array[String]) }
      def self.constraint_paths(file)
        references(file).select(&:constraint).map(&:path).uniq
      end

      sig { params(file: Dependabot::DependencyFile).returns(T::Array[Reference]) }
      def self.references(file)
        content = file.content
        return [] if content.nil?

        current_dir = File.dirname(file.name)
        logical_lines(content).flat_map do |line|
          reference_options(line).filter_map do |path, constraint|
            next unless path.end_with?(*REQUIREMENT_FILE_EXTENSIONS)

            resolved = current_dir == "." ? path : File.join(current_dir, path)
            Reference.new(path: Pathname.new(resolved).cleanpath.to_path, constraint: constraint)
          end
        end
      end

      sig { params(content: String, strip_comments: T::Boolean).returns(T::Array[String]) }
      def self.logical_lines(content, strip_comments: true)
        lines = T.let([], T::Array[String])
        continued = T.let(+"", String)

        content.each_line(chomp: true) do |line|
          if line.end_with?("\\") && !line.match?(COMMENT_PATTERN)
            continued << line.delete_suffix("\\")
            next
          end

          continued << line
          logical_line = strip_comments ? continued.sub(COMMENT_PATTERN, "").strip : continued
          lines << logical_line unless logical_line.strip.empty?
          continued = +""
        end

        unless continued.empty?
          logical_line = strip_comments ? continued.sub(COMMENT_PATTERN, "").strip : continued
          lines << logical_line unless logical_line.strip.empty?
        end

        lines
      end

      sig { params(line: String).returns(T::Array[[String, T::Boolean]]) }
      private_class_method def self.reference_options(line)
        tokens = Shellwords.split(line)
        references = T.let([], T::Array[[String, T::Boolean]])
        index = 0

        while index < tokens.length
          token = T.must(tokens[index])
          path, constraint, consumed = reference_option(token, tokens[index + 1])
          references << [path, constraint] if path
          index += consumed
        end

        references
      rescue ArgumentError
        []
      end

      sig { params(token: String, following_token: T.nilable(String)).returns(ParsedReferenceOption) }
      private_class_method def self.reference_option(token, following_token)
        if SEPARATED_REFERENCE_OPTIONS.key?(token)
          return [following_token, T.must(SEPARATED_REFERENCE_OPTIONS[token]), 2]
        end

        short_match = token.match(/\A-(?<option>r|c)(?<path>.+)\z/)
        return [short_match[:path], short_match[:option] == "c", 1] if short_match

        long_match = token.match(/\A--(?<option>requirement|constraint)=(?<path>.+)\z/)
        return [long_match[:path], long_match[:option] == "constraint", 1] if long_match

        [nil, false, 1]
      end
    end
  end
end
