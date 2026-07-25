# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/powershell/content_masker"

RSpec.describe Dependabot::Powershell::ContentMasker do
  describe ".mask" do
    it "preserves the original length and newline positions" do
      content = "line one\nline two\n<# comment #>\nline four\n"
      masked = described_class.mask(content)

      expect(masked.length).to eq(content.length)
      expect(masked.count("\n")).to eq(content.count("\n"))
    end

    it "blanks out block comments" do
      content = "before\n<#\nRequiredModules = @('FakeModule')\n#>\nafter"
      masked = described_class.mask(content)

      expect(masked).not_to include("FakeModule")
      expect(masked).to include("before")
      expect(masked).to include("after")
    end

    it "blanks out an unterminated block comment through the end of the content" do
      content = "before\n<# never closed RequiredModules = @('Fake')"
      masked = described_class.mask(content)

      expect(masked).not_to include("Fake")
      expect(masked).to include("before")
    end

    it "blanks out line comments" do
      content = "# RequiredModules = @('OldModule')\nRequiredModules = @('Real')"
      masked = described_class.mask(content)

      expect(masked).not_to include("OldModule")
      expect(masked).to include("RequiredModules = @('Real')")
    end

    it "does not blank a line comment's newline" do
      content = "# comment\ncode"
      masked = described_class.mask(content)

      expect(masked).to eq("         \ncode")
    end

    it "leaves an active #Requires -Modules directive untouched" do
      content = "#Requires -Modules Az.Real\nWrite-Host 'hi'"
      masked = described_class.mask(content)

      expect(masked).to include("#Requires -Modules Az.Real")
    end

    it "blanks out a #Requires -Modules example inside a regular comment" do
      content = "# Example: #Requires -Modules FakeModule\n#Requires -Modules Az.Real"
      masked = described_class.mask(content)

      expect(masked).not_to include("FakeModule")
      expect(masked).to include("#Requires -Modules Az.Real")
    end

    it "blanks out double-quoted here-strings, including a fake directive inside them" do
      content = <<~POWERSHELL
        #Requires -Modules Az.Real
        $example = @"
        #Requires -Modules FakeModule
        "@
        Write-Host $example
      POWERSHELL
      masked = described_class.mask(content)

      expect(masked).not_to include("FakeModule")
      expect(masked).to include("#Requires -Modules Az.Real")
      expect(masked).to include("Write-Host $example")
    end

    it "blanks out single-quoted here-strings" do
      content = "$example = @'\nRequiredModules = @('FakeModule')\n'@\nafter"
      masked = described_class.mask(content)

      expect(masked).not_to include("FakeModule")
      expect(masked).to include("after")
    end

    it 'does not treat @" as a here-string opener when other code follows it on the same line' do
      content = "$x = @\"value\" # RequiredModules = @('Fake')"
      masked = described_class.mask(content)

      expect(masked).to include('$x = @"value"')
      expect(masked).not_to include("Fake")
    end

    it "leaves quoted strings (which may contain # or <#) untouched" do
      content = "$x = 'a # not a comment'\n$y = \"<# not a block comment #>\""
      masked = described_class.mask(content)

      expect(masked).to include("$x = 'a # not a comment'")
      expect(masked).to include('$y = "<# not a block comment #>"')
    end

    it "handles a doubled single-quote escape inside a single-quoted string" do
      content = "$x = 'It''s a test # not a comment'\nafter"
      masked = described_class.mask(content)

      expect(masked).to include("$x = 'It''s a test # not a comment'")
      expect(masked).to include("after")
    end

    it "handles a backtick escape inside a double-quoted string" do
      content = "$x = \"a `\" # still inside the string\"\nafter"
      masked = described_class.mask(content)

      expect(masked).to include("after")
    end

    it "blanks a #Requires -Modules line that only appears as an interior line of a " \
       "multi-line double-quoted string" do
      content = <<~POWERSHELL
        #Requires -Modules Az.Real
        $description = "some text
        #Requires -Modules @{ModuleName='Fake'; RequiredVersion='1.0.0'}
        more text"
        Write-Host $description
      POWERSHELL
      masked = described_class.mask(content)

      expect(masked).not_to include("Fake")
      expect(masked).to include("#Requires -Modules Az.Real")
      expect(masked).to include("Write-Host $description")
    end

    it "runs in roughly linear time on adversarial unterminated block-comment openers" do
      content = ("<#" * 20_000) + "\n"

      start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      described_class.mask(content)
      elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - start_time

      expect(elapsed).to be < 2
    end
  end

  describe ".mask_quoted_strings" do
    it "preserves length and blanks a quoted string's interior while keeping its delimiters" do
      content = "Description = 'See RequiredModules = @(Fake) for details'\nafter"
      masked = described_class.mask_quoted_strings(content)

      expect(masked.length).to eq(content.length)
      expect(masked).not_to include("RequiredModules")
      expect(masked).to include("Description = '")
      expect(masked).to include("after")
    end

    it "blanks a double-quoted string's interior too" do
      content = "Description = \"RequiredModules = @('Fake')\""
      masked = described_class.mask_quoted_strings(content)

      expect(masked).not_to include("RequiredModules")
      expect(masked).to include("Description = \"")
    end

    it "leaves text outside of quoted strings untouched" do
      content = "RequiredModules = @('Az.Real')"
      masked = described_class.mask_quoted_strings(content)

      expect(masked).to start_with("RequiredModules = @('")
      expect(masked).to end_with("')")
      expect(masked.length).to eq(content.length)
      expect(masked).not_to include("Az.Real")
    end

    it "handles a doubled single-quote escape without terminating the string early" do
      content = "'It''s RequiredModules = @(Fake)'\nafter"
      masked = described_class.mask_quoted_strings(content)

      expect(masked.length).to eq(content.length)
      expect(masked).not_to include("RequiredModules")
      expect(masked).to include("after")
    end

    it "handles a backtick-escaped quote inside a double-quoted string without terminating early" do
      content = "Description = \"Example `\" RequiredModules = @('Fake')\"\nafter"
      masked = described_class.mask_quoted_strings(content)

      expect(masked.length).to eq(content.length)
      expect(masked).not_to include("RequiredModules")
      expect(masked).to include("after")
    end
  end
end
