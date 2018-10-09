# frozen_string_literal: true

# This module provides a (hopefully temporary) way to convert outline tables
# generated from dumping TomlRB into inline tables which are understood by
# Pipenv.
#
# This is required because Pipenv doesn't currently support outline tables.
# We have an issue open for that: https://github.com/pypa/pipenv/issues/2960
module TomlConverter
  PIPENV_OUTLINE_TABLES_REGEX = /
    \[(?<type>(dev-)?packages)\.(?<name>[^\]]+)\]
    (?<content>.*?)(?=^\[|\z)
  /mx

  def self.convert_pipenv_outline_tables(content)
    # First, find any outline tables that appear in the Pipfile
    matches = []
    content.scan(PIPENV_OUTLINE_TABLES_REGEX) { matches << Regexp.last_match }

    # Next, remove all of them. We'll add them back in as inline tables next
    updated_content = content.gsub(PIPENV_OUTLINE_TABLES_REGEX, "")

    # Iterate through each of the outline tables we found, adding it back to the
    # Pipfile as an inline table
    matches.each do |match|
      # If the heading for this section doesn't yet exist in the Pipfile, add it
      unless updated_content.include?(match[:type])
        updated_content += "\n\n[#{match[:type]}]\n"
      end

      # Build the inline table contents from the contents of the outline table
      inline_content = match[:content].strip.gsub(/\s*\n+/, ", ")
      content_to_insert = "#{match[:name]} = {#{inline_content}}"

      # Insert the created inline table just below the heading for the correct
      # section
      updated_content.sub!(
        "[#{match[:type]}]\n",
        "[#{match[:type]}]\n#{content_to_insert}\n"
      )
    end

    # Return the updated content
    updated_content
  end
end
