require "spec_helper"

# Rails flushes Rails.logger after every request (Rails::Rack::Logger calls
# ActiveSupport::LogSubscriber.flush_all!), and Logger#flush returns right away for that call
# instead of waiting for delivery. These run ActiveSupport's real flush_all! in another process, so
# an ActiveSupport that calls flush differently fails here. The ingesting host holds its answers
# until the direct flush, so a flush_all! that waited for delivery would take 5 seconds.
describe Logtail::Logger, "#flush called by ActiveSupport::LogSubscriber.flush_all!" do
  {
    "a Logtail::Logger" => "logger",
    "a Logtail::Logger in ActiveSupport::TaggedLogging" => "ActiveSupport::TaggedLogging.new(logger)",
    "a Logtail::Logger in an ActiveSupport::BroadcastLogger, as Rails 7.1 and later wrap it" =>
      "ActiveSupport::BroadcastLogger.new(logger)",
    "a Logtail::Logger in ActiveSupport::TaggedLogging in an ActiveSupport::BroadcastLogger" =>
      "ActiveSupport::BroadcastLogger.new(ActiveSupport::TaggedLogging.new(logger))"
  }.each do |description, rails_logger|
    it "returns right away for #{description}, and flushing it directly delivers" do
      if rails_logger.include?("BroadcastLogger") && Gem.loaded_specs["activesupport"].version < Gem::Version.new("7.1")
        skip "ActiveSupport::BroadcastLogger was added in ActiveSupport 7.1"
      end

      result = run_ruby(<<-RUBY)
        require "logger" # ActiveSupport 6.1 needs it loaded first since concurrent-ruby 1.3.5
        require "active_support"
        require "active_support/log_subscriber"
        require "active_support/tagged_logging"
        require "json"
        require "logtail"

        # The ingesting host keeps the lines of every request, but answers only once `answering` is set
        delivered = []
        answering = false
        server = TCPServer.new("127.0.0.1", 0)
        Thread.new do
          loop do
            Thread.new(server.accept) do |socket|
              while socket.gets
                length = 0
                while (header = socket.gets) != "\\r\\n"
                  length = header.split(":")[1].to_i if header.downcase.start_with?("content-length:")
                end
                delivered.concat(MessagePack.unpack(Zlib::Inflate.inflate(socket.read(length))).map { |line| line["message"] })
                sleep 0.01 until answering
                socket.write("HTTP/1.1 202 Accepted\\r\\nContent-Length: 0\\r\\n\\r\\n")
              end
            end
          end
        end

        # Logs a line for every request, like Rails' ActionController::LogSubscriber
        class RequestLogSubscriber < ActiveSupport::LogSubscriber
          def request(event)
            info(event.payload[:message])
          end
        end
        RequestLogSubscriber.attach_to(:app)

        logger = Logtail::Logger.new(Logtail::LogDevices::HTTP.new("token", flush_interval: 60,
          ingesting_host: "127.0.0.1", ingesting_port: server.addr[1], ingesting_scheme: "http"))
        ActiveSupport::LogSubscriber.logger = #{rails_logger}
        ActiveSupport::Notifications.instrument("request.app", message: "Completed 200 OK")

        flushing = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        ActiveSupport::LogSubscriber.flush_all!
        flush_all_seconds = Process.clock_gettime(Process::CLOCK_MONOTONIC) - flushing
        delivered_by_flush_all = delivered.dup

        answering = true
        ActiveSupport::LogSubscriber.logger.flush
        puts JSON.generate("flush_all_seconds" => flush_all_seconds, "delivered_by_flush_all" => delivered_by_flush_all,
          "delivered_by_flush" => delivered.drop(delivered_by_flush_all.size))
      RUBY

      expect(result.status).to be_success, result.stderr
      expect(JSON.parse(result.stdout)).to match(
        "flush_all_seconds" => a_value < 1,
        "delivered_by_flush_all" => [],
        "delivered_by_flush" => ["Completed 200 OK"]
      )
    end
  end
end
