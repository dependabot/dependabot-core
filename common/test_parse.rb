require 'dependabot/requirement'

# Test if ">= 12.a" can be parsed
begin
  req = Dependabot::Requirement.requirements_array(">= 12.a")
  puts "Parsed successfully: #{req.inspect}"
rescue => e
  puts "ERROR: #{e.class}: #{e.message}"
end
