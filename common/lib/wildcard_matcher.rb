# frozen_string_literal: true

class WildcardMatcher
  def self.match?(wildcard_string, candidate_string)
    return false unless wildcard_string && candidate_string

    regex_string = "a#{wildcard_string.downcase}a".split("*").
                   map { |p| Regexp.quote(p) }.
                   join(".*").gsub(/^a|a$/, "")
    regex = /^#{regex_string}$/
    regex.match?(candidate_string.downcase)
  end
end
