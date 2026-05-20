# typed: strict
# frozen_string_literal: true

require "sorbet-runtime"

module Dependabot
  # Provides helpers for emitting GitHub Actions workflow commands to STDOUT.
  # These commands are parsed by the Actions runner to create annotations,
  # collapsible log groups, and mask secrets.
  #
  # @see https://docs.github.com/en/actions/using-workflows/workflow-commands-for-github-actions
  module GitHubActionsWorkflowCommands
    extend T::Sig

    # Emit a notice annotation visible in the workflow summary.
    sig do
      params(
        message: String,
        title: T.nilable(String),
        file: T.nilable(String),
        line: T.nilable(Integer),
        end_line: T.nilable(Integer),
        col: T.nilable(Integer),
        end_col: T.nilable(Integer)
      ).void
    end
    def self.notice(message, title: nil, file: nil, line: nil, end_line: nil, col: nil, end_col: nil)
      emit_command("notice", message, title: title, file: file, line: line,
                                      end_line: end_line, col: col, end_col: end_col)
    end

    # Emit a warning annotation visible in the workflow summary.
    sig do
      params(
        message: String,
        title: T.nilable(String),
        file: T.nilable(String),
        line: T.nilable(Integer),
        end_line: T.nilable(Integer),
        col: T.nilable(Integer),
        end_col: T.nilable(Integer)
      ).void
    end
    def self.warning(message, title: nil, file: nil, line: nil, end_line: nil, col: nil, end_col: nil)
      emit_command("warning", message, title: title, file: file, line: line,
                                       end_line: end_line, col: col, end_col: end_col)
    end

    # Emit an error annotation visible in the workflow summary.
    sig do
      params(
        message: String,
        title: T.nilable(String),
        file: T.nilable(String),
        line: T.nilable(Integer),
        end_line: T.nilable(Integer),
        col: T.nilable(Integer),
        end_col: T.nilable(Integer)
      ).void
    end
    def self.error(message, title: nil, file: nil, line: nil, end_line: nil, col: nil, end_col: nil)
      emit_command("error", message, title: title, file: file, line: line,
                                     end_line: end_line, col: col, end_col: end_col)
    end

    # Create a collapsible log group. Use with a block:
    #
    #   GitHubActionsWorkflowCommands.group("Updating dependencies") do
    #     puts "Updating foo..."
    #   end
    sig do
      type_parameters(:T)
        .params(title: String, blk: T.proc.returns(T.type_parameter(:T)))
        .returns(T.type_parameter(:T))
    end
    def self.group(title, &blk)
      puts "::group::#{title}"
      result = blk.call
      puts "::endgroup::"
      result
    end

    # Mask a value so it is redacted from all subsequent log output.
    sig { params(value: String).void }
    def self.add_mask(value)
      puts "::add-mask::#{value}"
    end

    sig do
      params(
        command: String,
        message: String,
        title: T.nilable(String),
        file: T.nilable(String),
        line: T.nilable(Integer),
        end_line: T.nilable(Integer),
        col: T.nilable(Integer),
        end_col: T.nilable(Integer)
      ).void
    end
    private_class_method def self.emit_command(command, message, title:, file:, line:, end_line:, col:, end_col:)
      params = build_params(title: title, file: file, line: line, end_line: end_line, col: col, end_col: end_col)
      param_str = params.empty? ? "" : " #{params}"
      puts "::#{command}#{param_str}::#{escape_data(message)}"
    end

    sig do
      params(
        title: T.nilable(String),
        file: T.nilable(String),
        line: T.nilable(Integer),
        end_line: T.nilable(Integer),
        col: T.nilable(Integer),
        end_col: T.nilable(Integer)
      ).returns(String)
    end
    private_class_method def self.build_params(title:, file:, line:, end_line:, col:, end_col:)
      pairs = []
      pairs << "title=#{escape_property(title)}" if title
      pairs << "file=#{escape_property(file)}" if file
      pairs << "line=#{line}" if line
      pairs << "endLine=#{end_line}" if end_line
      pairs << "col=#{col}" if col
      pairs << "endColumn=#{end_col}" if end_col
      pairs.join(",")
    end

    # Escape characters that have special meaning in workflow command data.
    sig { params(value: String).returns(String) }
    private_class_method def self.escape_data(value)
      value.gsub("%", "%25")
           .gsub("\r", "%0D")
           .gsub("\n", "%0A")
    end

    # Escape characters that have special meaning in workflow command properties.
    sig { params(value: String).returns(String) }
    private_class_method def self.escape_property(value)
      value.gsub("%", "%25")
           .gsub("\r", "%0D")
           .gsub("\n", "%0A")
           .gsub(":", "%3A")
           .gsub(",", "%2C")
    end
  end
end
