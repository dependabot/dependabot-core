# frozen_string_literal: true

# This module provides a (hopefully temporary) way to convert outline tables
# generated from dumping TomlRB into inline tables which are understood by
# Pipenv.
module TomlConverter
  PIPENV_OUTLINE_TABLES_REGEX = /
    \[(?<type>(dev-)?packages)\.(?<name>[^\]]+)\]
    (?<content>.*?)(?=^\[|\z)
  /mx

  def self.convert_pipenv_outline_tables(content)
    matches = []
    content.scan(PIPENV_OUTLINE_TABLES_REGEX) { matches << Regexp.last_match }

    updated_content = content.gsub(PIPENV_OUTLINE_TABLES_REGEX, "")

    matches.each do |match|
      unless updated_content.include?(match[:type])
        updated_content += "\n\n[#{match[:type]}]\n"
      end

      inline_content = match[:content].strip.gsub(/\s*\n+/, ", ")
      content_to_insert = "#{match[:name]} = {#{inline_content}}"

      updated_content.sub!(
        "[#{match[:type]}]\n",
        "[#{match[:type]}]\n#{content_to_insert}\n"
      )
    end

    updated_content
  end
end
