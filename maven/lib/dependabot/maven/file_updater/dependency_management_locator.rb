# typed: strict
# frozen_string_literal: true

require "rexml/parsers/baseparser"
require "stringio"
require "dependabot/maven/file_updater"

module Dependabot
  module Maven
    class FileUpdater < Dependabot::FileUpdaters::Base
      class DependencyManagementLocator
        extend T::Sig

        sig { params(content: String).void }
        def initialize(content)
          @stream = T.let(StringIO.new(content), StringIO)
          @parser = T.let(REXML::Parsers::BaseParser.new(@stream), REXML::Parsers::BaseParser)
        end

        sig { params(project_name: String, element_name: String).returns(T::Range[Integer]) }
        def replacement_range(project_name:, element_name:)
          path = T.let([], T::Array[String])
          element_start = T.let(nil, T.nilable(Integer))

          loop do
            start = byte_position
            event = @parser.pull
            case event.first
            when :start_element
              path << event[1]
              element_start = start if path == [project_name, element_name]
            when :end_element
              return T.must(element_start)...byte_position if path == [project_name, element_name]
              return insertion_range(start) if path == [project_name]

              path.pop
            when :end_document
              raise "Could not locate project dependency management in the XML content"
            end
          end
        end

        private

        sig { params(start: Integer).returns(T::Range[Integer]) }
        def insertion_range(start)
          raise "Cannot insert dependency management into a self-closing <project> element" if start == byte_position

          start...start
        end

        # REXML reads ahead and compacts its buffer. Subtract unread bytes from the IO
        # position, converting the decoded buffer back to the document's encoding.
        sig { returns(Integer) }
        def byte_position
          @stream.pos - @parser.source.buffer.encode(@parser.source.encoding).bytesize
        end
      end
    end
  end
end
