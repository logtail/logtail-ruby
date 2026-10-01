require "spec_helper"

# What the HTTP device does while the process that logs with it exits. These run logtail in a
# real Ruby process, and count what reaches a local ingesting server.
describe Logtail::LogDevices::HTTP, "when the process exits" do
  let(:ingest) { LocalIngestServer.new }

  after { ingest.stop }

  # A local port that nothing listens on, so connecting to it is refused.
  def unused_port
    server = TCPServer.new("127.0.0.1", 0)
    server.addr[1]
  ensure
    server.close
  end

  it "delivers a line that a thread logs while Ruby kills it at exit, without printing an error" do
    result = run_ruby(<<-RUBY)
      require "logtail"
      logger = Logtail::Logger.new(Logtail::LogDevices::HTTP.new("token", #{ingest.device_options}))
      logger.info("logged before exit")
      started = Queue.new
      Thread.new do
        begin
          started << true
          sleep
        ensure
          logger.info("logged by a thread that Ruby kills at exit")
        end
      end
      started.pop
    RUBY

    expect(result.stderr).not_to include("log writing failed")
    expect(ingest.messages).to contain_exactly("logged before exit", "logged by a thread that Ruby kills at exit")
  end

  it "delivers a line that an at_exit hook logs after the device closed" do
    result = run_ruby(<<-RUBY)
      require "logtail"
      logger = nil
      at_exit { logger.info("logged by an at_exit hook registered first, which runs last") }
      logger = Logtail::Logger.new(Logtail::LogDevices::HTTP.new("token", #{ingest.device_options}))
      logger.info("logged before exit")
    RUBY

    expect(result.status).to be_success, result.stderr
    expect(ingest.messages).to contain_exactly("logged before exit", "logged by an at_exit hook registered first, which runs last")
  end

  it "closes a device once at exit, however many loggers write to it" do
    result = run_ruby(<<-RUBY)
      require "logtail"
      closes = 0
      at_exit { puts "closes: " + closes.to_s }
      Logtail::LogDevices::HTTP.prepend(Module.new { define_method(:close) { closes += 1; super() } })
      device = Logtail::LogDevices::HTTP.new("token", #{ingest.device_options})
      3.times { |n| Logtail::Logger.new(device).info("line " + n.to_s) }
    RUBY

    expect(result.stdout).to eq("closes: 1\n"), result.stderr
    expect(ingest.messages).to contain_exactly("line 0", "line 1", "line 2")
  end

  it "exits within 5 seconds when the ingesting host can't be reached, however many loggers there are" do
    result = run_ruby(<<-RUBY)
      exiting = nil
      at_exit { puts Process.clock_gettime(Process::CLOCK_MONOTONIC) - exiting }
      require "logtail"
      device = Logtail::LogDevices::HTTP.new("token", ingesting_host: "127.0.0.1", ingesting_port: #{unused_port}, ingesting_scheme: "http")
      2.times { |n| Logtail::Logger.new(device).info("line " + n.to_s) }
      exiting = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    RUBY

    expect(result.status).to be_success, result.stderr
    expect(result.stdout.to_f).to be < 5
  end
end
