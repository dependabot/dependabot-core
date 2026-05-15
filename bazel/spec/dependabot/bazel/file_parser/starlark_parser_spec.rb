# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/bazel/file_parser/starlark_parser"

RSpec.describe Dependabot::Bazel::FileParser::StarlarkParser do
  let(:parser) { described_class.new(content) }

  describe "#parse_function_calls" do
    context "with simple function calls" do
      let(:content) do
        <<~BAZEL
          bazel_dep(name = "rules_cc", version = "0.1.1")
          bazel_dep(version = "1.2.3", name = "rules_go")
        BAZEL
      end

      it "parses keyword arguments in any order" do
        function_calls = parser.parse_function_calls

        expect(function_calls.length).to eq(2)

        first_call = function_calls[0]
        expect(first_call.name).to eq("bazel_dep")
        expect(first_call.arguments["name"]).to eq("rules_cc")
        expect(first_call.arguments["version"]).to eq("0.1.1")
        expect(first_call.positional_arguments).to be_empty
        expect(first_call.line).to eq(1)

        second_call = function_calls[1]
        expect(second_call.name).to eq("bazel_dep")
        expect(second_call.arguments["name"]).to eq("rules_go")
        expect(second_call.arguments["version"]).to eq("1.2.3")
        expect(second_call.positional_arguments).to be_empty
        expect(second_call.line).to eq(2)
      end
    end

    context "with positional arguments" do
      let(:content) do
        <<~BAZEL
          load("@rules_go//go:def.bzl", "go_library", "go_binary")
          load("@rules_cc//cc:defs.bzl", "cc_library")
        BAZEL
      end

      it "parses positional arguments correctly" do
        function_calls = parser.parse_function_calls

        expect(function_calls.length).to eq(2)

        first_call = function_calls[0]
        expect(first_call.name).to eq("load")
        expect(first_call.arguments).to be_empty
        expect(first_call.positional_arguments).to eq(
          [
            "@rules_go//go:def.bzl", "go_library", "go_binary"
          ]
        )

        second_call = function_calls[1]
        expect(second_call.name).to eq("load")
        expect(second_call.arguments).to be_empty
        expect(second_call.positional_arguments).to eq(
          [
            "@rules_cc//cc:defs.bzl", "cc_library"
          ]
        )
      end
    end

    context "with http_archive function" do
      let(:content) do
        <<~BAZEL
          http_archive(
              name = "rules_go",
              urls = [
                  "https://github.com/bazelbuild/rules_go/releases/download/v0.39.1/rules_go-v0.39.1.zip",
              ],
              sha256 = "6b65cb7917b4d1709f9410ffe00ecf3e160edf674b78c54a894471320862184f",
          )
        BAZEL
      end

      it "parses complex function calls with arrays" do
        function_calls = parser.parse_function_calls

        expect(function_calls.length).to eq(1)

        call = function_calls[0]
        expect(call.name).to eq("http_archive")
        expect(call.arguments["name"]).to eq("rules_go")
        expect(call.arguments["urls"]).to eq(
          [
            "https://github.com/bazelbuild/rules_go/releases/download/v0.39.1/rules_go-v0.39.1.zip"
          ]
        )
        expect(call.arguments["sha256"]).to eq("6b65cb7917b4d1709f9410ffe00ecf3e160edf674b78c54a894471320862184f")
      end
    end

    context "with git_repository function" do
      let(:content) do
        <<~BAZEL
          git_repository(
              name = "com_google_absl",
              remote = "https://github.com/abseil/abseil-cpp.git",
              tag = "20230125.3",
          )
        BAZEL
      end

      it "parses git repository declarations" do
        function_calls = parser.parse_function_calls

        expect(function_calls.length).to eq(1)

        call = function_calls[0]
        expect(call.name).to eq("git_repository")
        expect(call.arguments["name"]).to eq("com_google_absl")
        expect(call.arguments["remote"]).to eq("https://github.com/abseil/abseil-cpp.git")
        expect(call.arguments["tag"]).to eq("20230125.3")
      end
    end

    context "with different value types" do
      let(:content) do
        <<~BAZEL
          cc_library(
              name = "my_lib",
              srcs = ["lib.cc", "lib.h"],
              visibility = ["//visibility:public"],
              deps = [
                  "@com_google_absl//absl/strings",
                  "//some/other:target",
              ],
              copts = ["-Wall", "-Werror"],
              defines = ["MY_DEFINE=1"],
              testonly = True,
              linkstatic = False,
          )
        BAZEL
      end

      it "handles various parameter types" do
        function_calls = parser.parse_function_calls

        expect(function_calls.length).to eq(1)

        call = function_calls[0]
        expect(call.name).to eq("cc_library")
        expect(call.arguments["name"]).to eq("my_lib")
        expect(call.arguments["srcs"]).to eq(["lib.cc", "lib.h"])
        expect(call.arguments["visibility"]).to eq(["//visibility:public"])
        expect(call.arguments["deps"]).to eq(
          [
            "@com_google_absl//absl/strings",
            "//some/other:target"
          ]
        )
        expect(call.arguments["copts"]).to eq(["-Wall", "-Werror"])
        expect(call.arguments["defines"]).to eq(["MY_DEFINE=1"])
        expect(call.arguments["testonly"]).to be(true)
        expect(call.arguments["linkstatic"]).to be(false)
      end
    end

    context "with comments and whitespace" do
      let(:content) do
        <<~BAZEL
          # This is a comment
          bazel_dep(
              # Comment about name
              name = "rules_cc",  # Inline comment
              version = "0.1.1",
          )

          # Another comment
          load("@rules_go//go:def.bzl", "go_library")
        BAZEL
      end

      it "handles comments and extra whitespace" do
        function_calls = parser.parse_function_calls

        expect(function_calls.length).to eq(2)

        first_call = function_calls[0]
        expect(first_call.name).to eq("bazel_dep")
        expect(first_call.arguments["name"]).to eq("rules_cc")
        expect(first_call.arguments["version"]).to eq("0.1.1")

        second_call = function_calls[1]
        expect(second_call.name).to eq("load")
        expect(second_call.positional_arguments).to eq(["@rules_go//go:def.bzl", "go_library"])
      end
    end

    context "with empty functions" do
      let(:content) do
        <<~BAZEL
          empty_function()
          another_empty()
        BAZEL
      end

      it "handles functions with no arguments" do
        function_calls = parser.parse_function_calls

        expect(function_calls.length).to eq(2)

        first_call = function_calls[0]
        expect(first_call.name).to eq("empty_function")
        expect(first_call.arguments).to be_empty
        expect(first_call.positional_arguments).to be_empty

        second_call = function_calls[1]
        expect(second_call.name).to eq("another_empty")
        expect(second_call.arguments).to be_empty
        expect(second_call.positional_arguments).to be_empty
      end
    end

    context "with string escaping" do
      let(:content) do
        <<~BAZEL
          test_function(
              name = "test with \\"quotes\\"",
              path = "path/with\\\\backslash",
              newline = "line1\\nline2",
          )
        BAZEL
      end

      it "handles escaped characters in strings" do
        function_calls = parser.parse_function_calls

        expect(function_calls.length).to eq(1)

        call = function_calls[0]
        expect(call.name).to eq("test_function")
        expect(call.arguments["name"]).to eq('test with "quotes"')
        expect(call.arguments["path"]).to eq("path/with\\backslash")
        expect(call.arguments["newline"]).to eq("line1\nline2")
      end
    end

    context "with mixed keyword and positional arguments" do
      let(:content) do
        <<~BAZEL
          mixed_function("positional1", "positional2", name = "keyword_value", flag = True)
        BAZEL
      end

      it "handles both positional and keyword arguments" do
        function_calls = parser.parse_function_calls

        expect(function_calls.length).to eq(1)

        call = function_calls[0]
        expect(call.name).to eq("mixed_function")
        expect(call.positional_arguments).to eq(%w(positional1 positional2))
        expect(call.arguments["name"]).to eq("keyword_value")
        expect(call.arguments["flag"]).to be(true)
      end
    end

    context "with malformed syntax" do
      let(:content) do
        <<~BAZEL
          valid_function(name = "good")
          malformed_function(name = "unclosed string
          another_valid_function(version = "1.0.0")
        BAZEL
      end

      it "continues parsing after errors" do
        function_calls = parser.parse_function_calls

        # Should recover and parse at least the first valid function
        expect(function_calls.length).to be >= 1

        first_call = function_calls[0]
        expect(first_call.name).to eq("valid_function")
        expect(first_call.arguments["name"]).to eq("good")

        # The second function may or may not be parsed depending on error recovery
        if function_calls.length > 1
          second_call = function_calls[1]
          expect(second_call.name).to eq("another_valid_function")
          expect(second_call.arguments["version"]).to eq("1.0.0")
        end
      end
    end

    context "with line tracking" do
      let(:content) do
        <<~BAZEL
          # Line 1: comment
          first_function(name = "first")
          # Line 3: another comment

          second_function(
              name = "second"
          )
        BAZEL
      end

      it "tracks line numbers correctly" do
        function_calls = parser.parse_function_calls

        expect(function_calls.length).to eq(2)

        first_call = function_calls[0]
        expect(first_call.line).to eq(2)

        second_call = function_calls[1]
        expect(second_call.line).to eq(5)
      end
    end

    context "with nested structures" do
      let(:content) do
        <<~BAZEL
          complex_function(
              name = "complex",
              nested_list = [
                  ["inner1", "inner2"],
                  ["inner3", "inner4"],
              ],
              config = {
                  "key1": "value1",
                  "key2": ["list_in_dict"],
              }
          )
        BAZEL
      end

      it "handles nested data structures" do
        function_calls = parser.parse_function_calls

        expect(function_calls.length).to eq(1)

        call = function_calls[0]
        expect(call.name).to eq("complex_function")
        expect(call.arguments["name"]).to eq("complex")

        # The parser should handle nested arrays
        nested_list = call.arguments["nested_list"]
        expect(nested_list).to be_an(Array)
        expect(nested_list.length).to eq(2)
      end
    end
  end

  describe "error handling" do
    context "with invalid function names" do
      let(:content) { "123invalid_name()" }

      it "extracts valid parts from invalid input" do
        function_calls = parser.parse_function_calls
        expect(function_calls.length).to eq(1)
        expect(function_calls[0].name).to eq("invalid_name")
      end
    end

    context "with unmatched parentheses" do
      let(:content) { "function_name(" }

      it "handles unmatched parentheses gracefully" do
        function_calls = parser.parse_function_calls
        expect(function_calls).to be_empty
      end
    end

    context "with empty content" do
      let(:content) { "" }

      it "handles empty content" do
        function_calls = parser.parse_function_calls
        expect(function_calls).to be_empty
      end
    end

    context "with only comments" do
      let(:content) do
        <<~BAZEL
          # This is just a comment
          # Another comment
        BAZEL
      end

      it "handles content with only comments" do
        function_calls = parser.parse_function_calls
        expect(function_calls).to be_empty
      end
    end
  end

  describe "advanced parsing scenarios" do
    context "with very long function calls" do
      let(:content) do
        urls = (1..50).map { |i| "\"https://example.com/file#{i}.tar.gz\"" }.join(",\n                ")
        <<~BAZEL
          http_archive(
              name = "large_dependency",
              urls = [
                  #{urls}
              ],
              sha256 = "very_long_sha256_hash_that_might_cause_issues_with_parsing_buffer_overflow_or_similar_edge_cases",
          )
        BAZEL
      end

      it "handles very long function calls" do
        function_calls = parser.parse_function_calls

        expect(function_calls.length).to eq(1)
        call = function_calls[0]
        expect(call.name).to eq("http_archive")
        expect(call.arguments["name"]).to eq("large_dependency")
        expect(call.arguments["urls"]).to be_an(Array)
        expect(call.arguments["urls"].length).to eq(50)
      end
    end

    context "with deeply nested structures" do
      let(:content) do
        <<~BAZEL
          complex_rule(
              name = "deeply_nested",
              config = {
                  "level1": {
                      "level2": {
                          "level3": ["deeply", "nested", "array"],
                          "another_level3": {
                              "level4": "deep_value"
                          }
                      }
                  },
                  "parallel_branch": ["item1", "item2"]
              },
              array_of_dicts = [
                  {"key1": "value1", "key2": ["nested", "in", "dict"]},
                  {"key3": "value3", "key4": {"nested": "dict"}}
              ]
          )
        BAZEL
      end

      it "handles deeply nested data structures" do
        function_calls = parser.parse_function_calls

        expect(function_calls.length).to eq(1)
        call = function_calls[0]
        expect(call.name).to eq("complex_rule")
        expect(call.arguments["name"]).to eq("deeply_nested")

        # The parser should extract at least the basic structure
        expect(call.arguments).to have_key("config")
        expect(call.arguments).to have_key("array_of_dicts")
      end
    end

    context "with special characters in strings" do
      let(:content) do
        <<~BAZEL
          special_function(
              unicode_name = "测试_名称_with_unicode",
              path_with_spaces = "path with spaces/file name.txt",
              special_chars = "!@#$%^&*()[]{}|;:,.<>?",
              regex_pattern = "^[a-zA-Z0-9_.-]+@[a-zA-Z0-9_.-]+\\.[a-zA-Z]{2,}$",
              json_like = '{"key": "value", "number": 123, "bool": true}',
          )
        BAZEL
      end

      it "handles special characters and unicode in strings" do
        function_calls = parser.parse_function_calls

        expect(function_calls.length).to eq(1)
        call = function_calls[0]
        expect(call.name).to eq("special_function")
        expect(call.arguments["unicode_name"]).to eq("测试_名称_with_unicode")
        expect(call.arguments["path_with_spaces"]).to eq("path with spaces/file name.txt")
        expect(call.arguments["special_chars"]).to eq("!@#$%^&*()[]{}|;:,.<>?")
        expect(call.arguments["regex_pattern"]).to eq("^[a-zA-Z0-9_.-]+@[a-zA-Z0-9_.-]+.[a-zA-Z]{2,}$")
        expect(call.arguments["json_like"]).to eq('{"key": "value", "number": 123, "bool": true}')
      end
    end

    context "with multiple function calls on same line" do
      let(:content) do
        <<~BAZEL
          func1(name = "first"); func2(name = "second")
          func3(name = "third") func4(name = "fourth")
        BAZEL
      end

      it "handles multiple function calls with various separators" do
        function_calls = parser.parse_function_calls

        # Should parse at least some of the functions
        expect(function_calls.length).to be >= 2

        names = function_calls.map(&:name)
        expect(names).to include("func1")
        expect(names).to include("func3")
      end
    end

    context "with numeric values" do
      let(:content) do
        <<~BAZEL
          numeric_function(
              integer = 42,
              float_val = 3.14159,
              zero = 0,
              large_number = 1500000,
          )
        BAZEL
      end

      it "handles various numeric formats" do
        function_calls = parser.parse_function_calls

        expect(function_calls.length).to eq(1)
        call = function_calls[0]
        expect(call.name).to eq("numeric_function")
        expect(call.arguments["integer"]).to eq(42)
        expect(call.arguments["float_val"]).to eq(3.14159)
        expect(call.arguments["zero"]).to eq(0)
        expect(call.arguments["large_number"]).to eq(1_500_000)
      end
    end

    context "with boolean and None values" do
      let(:content) do
        <<~BAZEL
          boolean_function(
              true_val = True,
              false_val = False,
              none_val = None,
              mixed_list = [True, False, None, "string", 123],
          )
        BAZEL
      end

      it "correctly parses boolean and None values" do
        function_calls = parser.parse_function_calls

        expect(function_calls.length).to eq(1)
        call = function_calls[0]
        expect(call.name).to eq("boolean_function")
        expect(call.arguments["true_val"]).to be(true)
        expect(call.arguments["false_val"]).to be(false)
        expect(call.arguments["none_val"]).to be_nil

        mixed_list = call.arguments["mixed_list"]
        expect(mixed_list).to be_an(Array)
        expect(mixed_list).to include(true, "string", 123)
        # NOTE: Complex array parsing with mixed types may have limitations
      end
    end

    context "with function calls in comments" do
      let(:content) do
        <<~BAZEL
          # This is not a function call: fake_function(name = "fake")
          real_function(name = "real")
          # Multi-line comment with
          # another_fake_function(name = "also_fake")
          # more comment lines
          another_real_function(name = "also_real")
        BAZEL
      end

      it "ignores function calls within comments" do
        function_calls = parser.parse_function_calls

        expect(function_calls.length).to eq(2)
        names = function_calls.map(&:name)
        expect(names).to contain_exactly("real_function", "another_real_function")

        # Should not include the fake functions from comments
        expect(names).not_to include("fake_function", "another_fake_function")
      end
    end

    context "with extremely malformed input" do
      let(:content) do
        <<~BAZEL
          valid_before()
          )))((([[[broken_syntax
          function_with_unclosed(param = "value"

          ,,,,invalid,syntax,here,,,,

          another_valid_function(name = "test")

          @#$%^&*()invalid_characters_everywhere@#$%^&*()

          final_valid_function(param = "final")
        BAZEL
      end

      it "recovers from extremely malformed input" do
        function_calls = parser.parse_function_calls

        # Should parse at least some valid functions despite the malformed syntax
        valid_names = function_calls.map(&:name)
        expect(valid_names).to include("valid_before")

        # May or may not parse functions after malformed sections depending on error recovery
        # The parser should be robust enough to not crash
        expect(function_calls).to be_an(Array)
      end
    end

    context "with performance stress test" do
      let(:content) do
        # Generate a large number of function calls to test performance
        calls = (1..100).map do |i|
          "test_function_#{i}(name = \"function_#{i}\", version = \"#{i}.0.0\", deps = [\"dep1\", \"dep2\"])"
        end.join("\n")
        calls
      end

      it "handles a large number of function calls efficiently" do
        start_time = Time.now
        function_calls = parser.parse_function_calls
        end_time = Time.now

        expect(function_calls.length).to eq(100)
        expect(end_time - start_time).to be < 5.0 # Should complete within 5 seconds

        # Verify some specific function calls
        first_call = function_calls[0]
        expect(first_call.name).to eq("test_function_1")
        expect(first_call.arguments["name"]).to eq("function_1")

        last_call = function_calls[99]
        expect(last_call.name).to eq("test_function_100")
        expect(last_call.arguments["name"]).to eq("function_100")
      end
    end
  end
end
