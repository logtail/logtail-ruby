# Prints the job matrix of the E2E workflow (.github/workflows/e2e.yml) as JSON.
#
#   ruby e2e/plan.rb [--leg all|floor|latest|canary] [--ruby <version>] [--msgpack <exact>] [--logger <exact>] [--source checkout|rubygems]
#
# floor   the oldest versions logtail.gemspec declares: the Ruby of required_ruby_version, and the oldest releases of
#         msgpack and logger on rubygems.org that its requirements accept
# latest  the newest stable Ruby that ruby/setup-ruby can install, with the newest msgpack and logger releases
# canary  ruby-head with the newest msgpack and logger releases. A pre-release newer than those is only reported.
#
# --ruby, --msgpack and --logger replace the planned version of every leg with one exact version, which is how a run
# bisects a failure to one release. --source is copied into every entry: checkout installs the gem built from this
# checkout, rubygems installs the newest release of logtail from rubygems.org.
#
# Standard library only, so the plan job needs nothing but a Ruby.
require "json"
require "net/http"
require "optparse"
require "rubygems"

module Plan
  ROOT = File.expand_path("..", __dir__)
  SETUP_RUBY_VERSIONS_URL = "https://raw.githubusercontent.com/ruby/setup-ruby/v1/ruby-builder-versions.json".freeze
  RUBYGEMS_VERSIONS_URL = "https://rubygems.org/api/v1/versions/%s.json".freeze
  LEGS = %w[floor latest canary].freeze
  DEPENDENCIES = %w[msgpack logger].freeze
  # Job names become artifact names (e2e-summary-<job name>), which must not contain any of these.
  NOT_IN_NAMES = ':"<>|*?/\\'.chars.freeze

  module_function

  # The Ruby that required_ruby_version (">= 2.3") names, as setup-ruby takes it: "2.3" installs the newest 2.3.x.
  def ruby_floor(spec)
    requirement = spec.required_ruby_version.requirements
    unless requirement.size == 1 && requirement[0][0] == ">="
      raise ArgumentError, "logtail.gemspec requires Ruby #{spec.required_ruby_version}, the plan reads only >= X.Y"
    end
    requirement[0][1].to_s
  end

  # The releases of a gem on rubygems.org, without pre-releases and platform builds (java, mingw), oldest first.
  def releases(versions)
    versions.select { |version| version["platform"] == "ruby" && !version["prerelease"] }
            .map { |version| Gem::Version.new(version["number"]) }.sort
  end

  # The oldest release the gemspec's requirement for the dependency accepts.
  def dependency_floor(spec, name, versions)
    dependency = spec.runtime_dependencies.find { |candidate| candidate.name == name }
    raise ArgumentError, "logtail.gemspec declares no dependency on #{name}" unless dependency

    floor = releases(versions).find { |version| dependency.requirement.satisfied_by?(version) }
    raise ArgumentError, "no release of #{name} satisfies #{dependency.requirement}" unless floor

    floor.to_s
  end

  def newest_release(versions)
    releases(versions).last.to_s
  end

  # The newest pre-release when it is newer than the newest release (msgpack 2.0.0.rc1 over 1.8.7), or nil.
  def newer_prerelease(versions)
    newest = releases(versions).last
    versions.select { |version| version["platform"] == "ruby" && version["prerelease"] }
            .map { |version| Gem::Version.new(version["number"]) }
            .select { |version| newest.nil? || version > newest }.max&.to_s
  end

  # The newest X.Y.Z in setup-ruby's list of CRuby builds, which also holds previews, head and debug builds.
  def newest_stable_ruby(builder_versions)
    builder_versions.fetch("ruby").grep(/\A\d+\.\d+\.\d+\z/).max_by { |version| Gem::Version.new(version) }
  end

  def job_name(leg, ruby, msgpack, logger)
    name = "#{leg} (Ruby #{ruby}, msgpack #{msgpack}, logger #{logger})"
    unless (name.chars & NOT_IN_NAMES).empty?
      raise ArgumentError, "job name #{name.inspect} contains one of #{NOT_IN_NAMES.join}, which artifact names do not allow"
    end
    name
  end

  def entry(leg, ruby, msgpack, logger, source, client)
    {
      leg: leg,
      name: job_name(leg, ruby, msgpack, logger),
      ruby: ruby,
      msgpack: msgpack,
      logger: logger,
      source: source,
      client: client,
      # The floor runs on the oldest Ubuntu image GitHub offers, the other legs follow ubuntu-latest.
      runner: leg == "floor" ? "ubuntu-24.04" : "ubuntu-latest",
    }
  end

  # A registry hiccup at schedule time should not file a Linear issue, so the lookup is retried.
  def fetch_json(url, attempts: 3)
    @fetched ||= {}
    @fetched[url] ||= begin
      attempt = 0
      begin
        attempt += 1
        response = Net::HTTP.get_response(URI(url))
        raise "HTTP #{response.code}" unless response.is_a?(Net::HTTPSuccess)
        JSON.parse(response.body)
      rescue StandardError => error
        abort "GET #{url} failed #{attempts} times, last: #{error.message}" if attempt == attempts
        sleep 10
        retry
      end
    end
  end

  def gem_versions(name)
    fetch_json(format(RUBYGEMS_VERSIONS_URL, name))
  end

  def plan(leg, spec, source, client, ruby: "", msgpack: "", logger: "")
    if leg == "floor"
      ruby = ruby_floor(spec) if ruby.empty?
      msgpack = dependency_floor(spec, "msgpack", gem_versions("msgpack")) if msgpack.empty?
      logger = dependency_floor(spec, "logger", gem_versions("logger")) if logger.empty?
    else
      ruby = (leg == "latest" ? newest_stable_ruby(fetch_json(SETUP_RUBY_VERSIONS_URL)) : "head") if ruby.empty?
      msgpack = newest_release(gem_versions("msgpack")) if msgpack.empty?
      logger = newest_release(gem_versions("logger")) if logger.empty?
    end
    entry(leg, ruby, msgpack, logger, source, client)
  end

  def main(argv)
    options = { leg: "all", ruby: "", msgpack: "", logger: "", source: "checkout" }
    OptionParser.new do |parser|
      parser.on("--leg LEG", ["all"] + LEGS) { |value| options[:leg] = value }
      parser.on("--ruby VERSION", "one Ruby version for every leg instead of the planned one") { |value| options[:ruby] = value.strip }
      parser.on("--msgpack VERSION", "one exact msgpack version for every leg instead of the planned one") { |value| options[:msgpack] = value.strip }
      parser.on("--logger VERSION", "one exact logger version for every leg instead of the planned one") { |value| options[:logger] = value.strip }
      parser.on("--source SOURCE", %w[checkout rubygems]) { |value| options[:source] = value }
    end.parse!(argv)

    # The gemspec lists its files with git ls-files, which needs the repository as the working directory.
    spec = Dir.chdir(ROOT) { Gem::Specification.load("logtail.gemspec") } || abort("logtail.gemspec does not load")
    # The checkout's version, or the newest release on rubygems.org, which a customer gets today.
    client = options[:source] == "rubygems" ? newest_release(gem_versions("logtail")) : spec.version.to_s
    legs = options[:leg] == "all" ? LEGS : [options[:leg]]
    include = legs.map do |leg|
      plan(leg, spec, options[:source], client, ruby: options[:ruby], msgpack: options[:msgpack], logger: options[:logger])
    end
    if legs.include?("canary")
      DEPENDENCIES.each do |name|
        prerelease = newer_prerelease(gem_versions(name))
        warn "::notice::#{name} #{prerelease} is newer than its newest release, the canary installs the release" if prerelease
      end
    end
    puts JSON.generate(include)
  rescue ArgumentError, OptionParser::ParseError => error
    abort error.message
  end
end

Plan.main(ARGV) if $PROGRAM_NAME == __FILE__
