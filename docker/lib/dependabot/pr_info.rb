require "cgi"
require "uri"

def pr_info(dependency)
  info = "More information can be found at: "
  if using_dockerhub? dependency then
    info << URI.join(
      "https://hub.docker.com/_/",
      CGI.escape(dependency.name) + "?" +
      URI.encode_www_form([
        ["tab", "tags"],
        ["name", dependency.version]
      ])
    ).to_s
  else
    info << URI.join("https://github.com/Pix4D/linux-image-build/releases/tag/",
                     CGI.escape("#{dependency.name}-#{dependency.version}")).to_s
  end
end

def using_dockerhub? dependency
  raise ArgumentError, "Dependency must have exactly one requirement" unless dependency.requirements.length == 1
  dependency.requirements.first[:source][:registry].nil?
end
