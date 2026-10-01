require "spec_helper"

# Forking servers and job runners (Puma, Unicorn, Resque) fork after the app logged. These run
# logtail in a real process that forks, and count what reaches a local ingesting server.
describe Logtail::LogDevices::HTTP, "after a fork" do
  let(:ingest) { LocalIngestServer.new }

  before do
    skip "needs fork" if !Process.respond_to?(:fork) || RUBY_ENGINE == "truffleruby"
  end

  after { ingest.stop }

  it "delivers the lines the parent logged before forking once, not once per process" do
    result = run_ruby(<<-RUBY)
      require "logtail"
      logger = Logtail::Logger.new(Logtail::LogDevices::HTTP.new("token", flush_interval: 60, #{ingest.device_options}))
      logger.info("parent line before the fork")
      2.times.map { |n| fork { logger.info("child line " + n.to_s) } }.each { |pid| Process.wait(pid) }
    RUBY

    expect(result.status).to be_success, result.stderr
    expect(ingest.messages).to contain_exactly("parent line before the fork", "child line 0", "child line 1")
  end

  it "delivers the lines a forked child logs" do
    result = run_ruby(<<-RUBY)
      require "logtail"
      logger = Logtail::Logger.new(Logtail::LogDevices::HTTP.new("token", flush_interval: 60, #{ingest.device_options}))
      Process.wait(fork { 3.times { |n| logger.info("child line " + n.to_s) } })
      logger.info("parent line after the fork")
    RUBY

    expect(result.status).to be_success, result.stderr
    expect(ingest.messages).to contain_exactly("child line 0", "child line 1", "child line 2", "parent line after the fork")
  end

  it "lets a child that hasn't logged exit right away, without waiting on the parent's lines" do
    result = run_ruby(<<-RUBY)
      require "logtail"
      logger = Logtail::Logger.new(Logtail::LogDevices::HTTP.new("token", flush_interval: 60, #{ingest.device_options}))
      logger.info("parent line before the fork")
      forking = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      Process.wait(fork {})
      puts Process.clock_gettime(Process::CLOCK_MONOTONIC) - forking
    RUBY

    expect(result.stdout.to_f).to be < 5
    expect(ingest.messages).to eq(["parent line before the fork"])
  end

  it "delivers a child's lines when it calls flush before leaving with exit!, which skips at_exit hooks" do
    result = run_ruby(<<-RUBY)
      require "logtail"
      logger = Logtail::Logger.new(Logtail::LogDevices::HTTP.new("token", flush_interval: 60, #{ingest.device_options}))
      logger.info("parent line")
      Process.wait(fork do
        begin
          logger.info("child line")
          logger.flush
        ensure
          exit!(0) # the way Resque ends a job's process
        end
      end)
    RUBY

    expect(result.status).to be_success, result.stderr
    expect(ingest.messages).to contain_exactly("parent line", "child line")
  end
end
