# Tests the version picking of e2e/plan.rb on fixed registry answers: ruby e2e/plan_test.rb
require "minitest/autorun"
require_relative "plan"

class PlanTest < Minitest::Test
  # As rubygems.org's versions API lists them, newest first, with platform builds and pre-releases.
  MSGPACK = [
    { "number" => "2.0.0.rc1", "platform" => "ruby", "prerelease" => true },
    { "number" => "1.8.7", "platform" => "java", "prerelease" => false },
    { "number" => "1.8.7", "platform" => "ruby", "prerelease" => false },
    { "number" => "1.8.6", "platform" => "ruby", "prerelease" => false },
    { "number" => "1.0.0", "platform" => "x86-mingw32", "prerelease" => false },
    { "number" => "1.0.0", "platform" => "ruby", "prerelease" => false },
    { "number" => "1.0.0.rc1", "platform" => "ruby", "prerelease" => true },
    { "number" => "0.7.6", "platform" => "ruby", "prerelease" => false },
  ].freeze
  # logger never had a 1.0.0: the oldest 1.x on rubygems.org is 1.2.7.1, newer than 1.3.0 only by publication date.
  LOGGER = [
    { "number" => "1.7.0", "platform" => "ruby", "prerelease" => false },
    { "number" => "1.3.0", "platform" => "ruby", "prerelease" => false },
    { "number" => "1.2.8.1", "platform" => "ruby", "prerelease" => false },
    { "number" => "1.2.7.1", "platform" => "ruby", "prerelease" => false },
  ].freeze

  def spec(required_ruby_version = ">= 2.3")
    Gem::Specification.new do |spec|
      spec.name = "logtail"
      spec.version = "0.1.21"
      spec.required_ruby_version = required_ruby_version
      spec.add_dependency("msgpack", "~> 1.0")
      spec.add_dependency("logger", "~> 1.0")
    end
  end

  def test_ruby_floor_is_the_version_of_required_ruby_version
    assert_equal "2.3", Plan.ruby_floor(spec)
  end

  def test_ruby_floor_refuses_anything_but_a_lower_bound
    assert_raises(ArgumentError) { Plan.ruby_floor(spec([">= 2.3", "< 4"])) }
  end

  def test_dependency_floor_is_the_oldest_release_the_requirement_accepts
    assert_equal "1.0.0", Plan.dependency_floor(spec, "msgpack", MSGPACK)
    assert_equal "1.2.7.1", Plan.dependency_floor(spec, "logger", LOGGER)
  end

  def test_newest_release_skips_pre_releases_and_platform_builds
    assert_equal "1.8.7", Plan.newest_release(MSGPACK)
    assert_equal "1.7.0", Plan.newest_release(LOGGER)
  end

  def test_newer_prerelease_only_above_the_newest_release
    assert_equal "2.0.0.rc1", Plan.newer_prerelease(MSGPACK)
    assert_nil Plan.newer_prerelease(LOGGER)
  end

  def test_newest_stable_ruby_skips_previews_and_head
    builder_versions = { "ruby" => ["3.4.9", "4.0.8", "4.0.9", "4.1.0-preview1", "head", "debug"] }
    assert_equal "4.0.9", Plan.newest_stable_ruby(builder_versions)
  end

  def test_entry
    assert_equal(
      { leg: "floor", name: "floor (Ruby 2.3, msgpack 1.0.0, logger 1.2.7.1)", ruby: "2.3", msgpack: "1.0.0",
        logger: "1.2.7.1", source: "checkout", client: "0.1.21", runner: "ubuntu-24.04" },
      Plan.entry("floor", "2.3", "1.0.0", "1.2.7.1", "checkout", "0.1.21")
    )
    assert_equal "ubuntu-latest", Plan.entry("canary", "head", "1.8.7", "1.7.0", "rubygems", "0.1.21")[:runner]
  end

  def test_job_names_refuse_what_artifact_names_do_not_allow
    assert_raises(ArgumentError) { Plan.job_name("latest", "4.0.9", "1.8.7", "1.7.0 / 2.0") }
  end
end
