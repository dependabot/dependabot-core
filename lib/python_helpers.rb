module PythonHelpers
  SEPARATOR_MATCH = /[===,==,>=,<=,<,>,~=,!=]/

  def self.parse_requirements(content)
    content.
      each_line.
      map(&:chomp).
      reject { |line| line.nil? || line.start_with?("#") }.
      select { |line| line.match(SEPARATOR_MATCH) }.
      map { |line| PythonHelpers.parse_line(line) }
  end

  def self.parse_line(line)
    name, _, version = line.split(SEPARATOR_MATCH)
    [name, version]
  end
end
