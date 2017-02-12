module PythonHelpers
  SEPARATOR_MATCH = /[===,==,>=,<=,<,>,~=,!=]/

  def self.requirements_parse(content)
    dependencies = []
    content.each_line.map(&:chomp).each do |line|
      next if line.start_with?("#") || line.nil?
      next if line.nil?
      next unless line.match(SEPARATOR_MATCH)
      dependencies << PythonHelpers.parse_line(line)
    end
    dependencies
  end

  def self.parse_line(line)
    name, _, version = line.split(SEPARATOR_MATCH)
    [name, version]
  end
end
