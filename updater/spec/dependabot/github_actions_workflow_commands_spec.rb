# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/github_actions_workflow_commands"

RSpec.describe Dependabot::GitHubActionsWorkflowCommands do
  describe ".notice" do
    it "emits a notice command" do
      expect { described_class.notice("Hello world") }
        .to output("::notice::Hello world\n").to_stdout
    end

    it "includes optional parameters" do
      expect { described_class.notice("msg", title: "Title", file: "foo.rb", line: 5) }
        .to output("::notice title=Title,file=foo.rb,line=5::msg\n").to_stdout
    end

    it "escapes newlines in the message" do
      expect { described_class.notice("line1\nline2") }
        .to output("::notice::line1%0Aline2\n").to_stdout
    end

    it "escapes colons and commas in property values" do
      expect { described_class.notice("msg", title: "a:b,c") }
        .to output("::notice title=a%3Ab%2Cc::msg\n").to_stdout
    end
  end

  describe ".warning" do
    it "emits a warning command" do
      expect { described_class.warning("Something concerning") }
        .to output("::warning::Something concerning\n").to_stdout
    end

    it "includes file and line parameters" do
      expect { described_class.warning("msg", file: "lib/foo.rb", line: 10, end_line: 12) }
        .to output("::warning file=lib/foo.rb,line=10,endLine=12::msg\n").to_stdout
    end
  end

  describe ".error" do
    it "emits an error command" do
      expect { described_class.error("Something broke") }
        .to output("::error::Something broke\n").to_stdout
    end

    it "includes all annotation parameters" do
      expect { described_class.error("msg", title: "Oops", file: "x.rb", line: 1, col: 5, end_col: 10) }
        .to output("::error title=Oops,file=x.rb,line=1,col=5,endColumn=10::msg\n").to_stdout
    end
  end

  describe ".group" do
    it "wraps output in group commands" do
      output = capture_stdout do
        described_class.group("My Group") { puts "inside" }
      end

      expect(output).to eq("::group::My Group\ninside\n::endgroup::\n")
    end

    it "returns the block's return value" do
      result = capture_stdout_and_result do
        described_class.group("G") { 42 }
      end

      expect(result).to eq(42)
    end
  end

  describe ".add_mask" do
    it "emits a mask command" do
      expect { described_class.add_mask("secret-token") }
        .to output("::add-mask::secret-token\n").to_stdout
    end
  end

  private

  def capture_stdout
    original = $stdout
    $stdout = StringIO.new
    yield
    $stdout.string
  ensure
    $stdout = original
  end

  def capture_stdout_and_result
    original = $stdout
    $stdout = StringIO.new
    result = yield
    result
  ensure
    $stdout = original
  end
end
