# typed: true
# frozen_string_literal: true

require "spec_helper"
require "dependabot/gradle/file_updater/declaration_scanner"

RSpec.describe Dependabot::Gradle::FileUpdater::DeclarationScanner do
  subject(:code_by_line) { described_class.new(content, kotlin: kotlin).code_by_line }

  let(:kotlin) { false }
  let(:content) { "" }

  context "with comments" do
    let(:content) do
      <<~GROOVY
        implementation 'a:b:1.0' /* note // text */
        implementation "c:d:1.0" // note
        implementation 'e:f:1.0' /* a 'quote */
        // don't
      GROOVY
    end

    it "removes them, keeping strings that look like comments" do
      code, = code_by_line
      expect(code.map(&:rstrip)).to eq(
        ["implementation 'a:b:1.0'", 'implementation "c:d:1.0"', "implementation 'e:f:1.0'", "", ""]
      )
    end
  end

  context "with a block comment that spans lines" do
    let(:content) { "implementation group: 'a', /* note\n  more */ name: 'b'\nimplementation 'c:d:1.0'\n" }

    it "puts the lines around it in one statement" do
      _, statement_of = code_by_line
      expect(statement_of).to eq([0, 0, 1, 2])
    end
  end

  context "with closures" do
    let(:content) do
      <<~GROOVY
        implementation('a:b:1.0') { because 'c:d is incompatible' }
        implementation(group: 'a', name: 'b', version: '1.0') { exclude group: 'c', module: 'd' }
        if (enabled(group: 'x', name: 'y')) { implementation 'a:b:1.0' }
        dependencies { implementation 'a:b:1.0' }
      GROOVY
    end

    it "blanks only the closures of dependency declarations" do
      code, = code_by_line
      expect(code.map { |line| line.squeeze(" ").rstrip }).to eq(
        [
          "implementation('a:b:1.0') { }",
          "implementation(group: 'a', name: 'b', version: '1.0') { }",
          "if (enabled(group: 'x', name: 'y')) { implementation 'a:b:1.0' }",
          "dependencies { implementation 'a:b:1.0' }",
          ""
        ]
      )
    end
  end

  context "with a Kotlin build script" do
    let(:kotlin) { true }
    let(:content) do
      <<~KOTLIN
        implementation("a:b:1.0") { because("c:d is incompatible") } /* see /* old */
        implementation("a:b:1.0").also { implementation("c:d:1.0") }
        if (enabled(
            name = "x")) { implementation("a:b:1.0") }
      KOTLIN
    end

    it "blanks declaration closures, ends comments at the first */, and keeps other bodies" do
      code, = code_by_line
      expect(code.map { |line| line.squeeze(" ").rstrip }).to eq(
        [
          'implementation("a:b:1.0") { }',
          'implementation("a:b:1.0").also { implementation("c:d:1.0") }',
          "if (enabled(",
          ' name = "x")) { implementation("a:b:1.0") }',
          ""
        ]
      )
    end
  end

  describe ".without_non_declaring_strings" do
    it "removes because reasons and project paths" do
      expect(
        described_class.without_non_declaring_strings(
          %{project("services:api") { implementation('a:b:1.0').because('Don\\'t use c:d') }}
        )
      ).to eq(") { implementation('a:b:1.0')) }")
    end

    it "handles an unterminated because reason with many backslashes quickly" do
      line = ".because(\"#{'\\a' * 40}"
      regex = Regexp.new(Dependabot::Gradle::FileUpdater::DeclarationScanner::BECAUSE_ARGUMENT_REGEX, timeout: 1)

      expect(regex.match?(line)).to be(false)
    end
  end
end
