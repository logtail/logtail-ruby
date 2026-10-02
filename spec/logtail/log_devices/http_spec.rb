require "spec_helper"
require "bigdecimal"
require "date"
require "set"

# Note: these tests access instance variables and private methods as a means of
# not muddying the public API. This object should expose a simple buffer like
# API, tests should not alter that.
describe Logtail::LogDevices::HTTP do
  describe "#initialize" do
    it "should initialize properly" do
      http = described_class.new("MYKEY", flush_interval: 0.1)

      # Ensure that threads have not started
      thread = http.instance_variable_get(:@flush_thread)
      expect(thread).to be_nil
      thread = http.instance_variable_get(:@request_outlet_thread)
      expect(thread).to be_nil
    end
  end

  describe "#write" do
    let(:http) { described_class.new("MYKEY") }
    let(:msg_queue) { http.instance_variable_get(:@msg_queue) }

    it "should buffer the messages" do
      http.write("test log message")
      expect(msg_queue.flush.map(&:message)).to eq(["test log message"])
      http.close
    end

    it "should start the flush threads" do
      http.write("test log message")

      thread = http.instance_variable_get(:@flush_thread)
      expect(thread).to be_alive
      thread = http.instance_variable_get(:@request_outlet_thread)
      expect(thread).to be_alive
      expect(http).to receive(:flush).exactly(1).times
      http.close
    end

    context "with a low batch size" do
      let(:http) { described_class.new("MYKEY", :batch_size => 2) }

      it "should attempt a delivery when the limit is exceeded" do
        http.write("test")
        expect(http).to receive(:flush_async).exactly(1).times
        http.write("my log message")
        expect(http).to receive(:flush).exactly(1).times
        http.close
      end
    end
  end

  describe "#close" do
    let(:http) { described_class.new("MYKEY") }

    it "should kill the threads" do
      http.send(:ensure_flush_threads_are_started)
      http.close
      thread = http.instance_variable_get(:@flush_thread)
      expect(thread).to_not be_alive
      thread = http.instance_variable_get(:@request_outlet_thread)
      expect(thread).to_not be_alive
    end

    it "should attempt a delivery" do
      message = "a" * 19
      http.write(message)
      expect(http).to receive(:flush).exactly(1).times
      http.close
    end
  end

  # Testing a private method because it helps break down our tests
  describe "#flush" do
    let(:time) { Time.utc(2016, 9, 1, 12, 0, 0) }

    it "should deliver the request" do
      http = described_class.new("MYKEY", flush_continuously: false)
      log_entry = Logtail::LogEntry.new("INFO", time, nil, "test log message 1", nil, nil)
      http.write(log_entry)
      log_entry = Logtail::LogEntry.new("INFO", time, nil, "test log message 2", nil, nil)
      http.write(log_entry)
      expect(http).to receive(:flush_async).exactly(2).times
      http.send(:flush)
      http.close
    end
  end

  # Testing a private method because it helps break down our tests
  describe "#flush_async" do
    let(:time) { Time.utc(2016, 9, 1, 12, 0, 0) }

    it "should add a request to the queue" do
      http = described_class.new("MYKEY", flush_continuously: false)
      log_entry = Logtail::LogEntry.new("INFO", time, nil, "test log message 1", nil, nil)
      http.write(log_entry)
      log_entry = Logtail::LogEntry.new("INFO", time, nil, "test log message 2", nil, nil)
      http.write(log_entry)
      http.send(:flush_async)
      request_queue = http.instance_variable_get(:@request_queue)
      request_attempt = request_queue.deq
      expect(request_attempt.request).to be_kind_of(Net::HTTP::Post)
      decompressed_body = Zlib::Inflate.inflate(request_attempt.request.body)
      expect(decompressed_body).to start_with("\x92\x84\xA5level\xA4INFO\xA2dt\xBB2016-09-01T12:00:00.000000Z\xA7message\xB2test log message 1".force_encoding("ASCII-8BIT"))

      message_queue = http.instance_variable_get(:@msg_queue)
      expect(message_queue.size).to eq(0)
    end
  end

  # Testing a private method because it helps break down our tests
  describe "#build_request" do
    let(:http) { described_class.new("MYKEY", flush_continuously: false) }
    let(:logger) { Logtail::Logger.new(http) }

    # Flushes the buffer and decodes the request body, the way the API reads it.
    def delivered_entries
      http.send(:flush_async)
      request = http.instance_variable_get(:@request_queue).deq.request
      MessagePack.unpack(Zlib::Inflate.inflate(request.body))
    end

    a_proc = proc {}
    an_object = Object.new
    a_cyclic_hash = { name: "parent" }
    a_cyclic_hash[:self] = a_cyclic_hash
    a_cyclic_array = ["parent"]
    a_cyclic_array << a_cyclic_array
    # Like a Rack::Session::SessionId, whose public id is the cookie of a server-side session
    a_session_id = Object.new
    def a_session_id.private_id
      "2::hashed-session-id"
    end
    def a_session_id.to_s
      "session-cookie"
    end

    {
      "a Time" => [Time.utc(2026, 10, 1, 12, 0, 0, 123456), "2026-10-01T12:00:00.123456Z"],
      "a Time with a UTC offset" => [Time.new(2026, 10, 1, 14, 0, 0, "+02:00"), "2026-10-01T12:00:00.000000Z"],
      "a DateTime" => [DateTime.new(2026, 10, 1, 14, 0, 0, "+02:00"), "2026-10-01T12:00:00.000000Z"],
      "a Date" => [Date.new(2026, 10, 1), "2026-10-01"],
      "a BigDecimal" => [BigDecimal("19.99"), "19.99"],
      "a Rational" => [Rational(1, 3), "1/3"],
      "an Integer above the 64-bit range" => [2**64, "18446744073709551616"],
      "an Integer below the 64-bit range" => [-2**63 - 1, "-9223372036854775809"],
      "a Set" => [Set[1, 2], [1, 2]],
      "a Struct" => [Struct.new(:id, :name).new(1, "Ann"), { "id" => 1, "name" => "Ann" }],
      "an Exception" => [ArgumentError.new("boom"), { "class" => "ArgumentError", "message" => "boom" }],
      "a Range" => [1..2, "1..2"],
      "a Class" => [String, "String"],
      "a Proc" => [a_proc, a_proc.to_s],
      "an arbitrary object" => [an_object, an_object.to_s],
      "an object with a private id" => [a_session_id, "2::hashed-session-id"],
      "a Hash that contains itself" => [a_cyclic_hash, { "name" => "parent", "self" => "[circular]" }],
      "an Array that contains itself" => [a_cyclic_array, ["parent", "[circular]"]],
    }.each do |description, (value, expected)|
      it "delivers the whole batch when a log line holds #{description}" do
        logger.info("line before")
        logger.info("line with the value", value: value)
        logger.info("line after")

        entries = delivered_entries
        expect(entries.map { |entry| entry["message"] }).to eq(["line before", "line with the value", "line after"])
        expect(entries[1]["value"]).to eq(expected)
      end
    end

    it "replaces a log line it still can't encode with one that says why, and delivers the rest" do
      unencodable = Object.new
      def unencodable.to_s
        raise "to_s failed"
      end

      logger.info("line before")
      logger.warn("line with the value", value: unencodable)
      logger.info("line after")

      entries = delivered_entries
      expect(entries.map { |entry| entry["message"] }).to eq([
        "line before",
        "Logtail could not encode this log line (RuntimeError: to_s failed): line with the value",
        "line after",
      ])
      expect(entries[1].keys).to contain_exactly("level", "dt", "message")
      expect(entries[1]["level"]).to eq("warn")
      expect(entries[1]["dt"]).to match(/\A\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d\.\d{6}Z\z/)
    end

    it "sends a log line that msgpack can encode as it is, without copying it" do
      hash = { message: "caf\u00E9", count: 1, ratio: 0.5, flag: true, none: nil, level: :info, nested: { list: [1, "two"] } }

      expect(http.send(:encodable_value, hash)).to be(hash)
    end

    it "passes strings that aren't valid UTF-8 to force_utf8_encoding, also in arrays and keys" do
      in_array = "in an array \xFF".b
      key = "key \xFF".b
      allow(http).to receive(:force_utf8_encoding).and_call_original

      logger.info("line", items: [in_array], counts: { key => 1 })
      delivered_entries

      expect(http).to have_received(:force_utf8_encoding).with(in_array)
      expect(http).to have_received(:force_utf8_encoding).with(key)
    end

    it "keeps the order of the keys of a hash when it converts some of them" do
      logger.info("line", value: { "a" => 1, Time.utc(2026, 10, 1) => 2, "c" => Date.new(2026, 10, 1) })

      expect(delivered_entries[0]["value"].to_a).to eq([["a", 1], ["2026-10-01T00:00:00.000000Z", 2], ["c", "2026-10-01"]])
    end

    it "leaves the logged values as they are" do
      value = { at: Time.utc(2026, 10, 1), nested: { on: Date.new(2026, 10, 1), list: [Set[1], "\xFF".b] } }
      original = Marshal.load(Marshal.dump(value))

      logger.info("line", value: value)
      delivered_entries

      expect(value).to eq(original)
    end

    it "delivers hashes and arrays nested 110 levels deep" do
      value = "leaf"
      110.times { |level| value = level.even? ? { "level #{level}" => value } : [value] }

      logger.info("line", value: value)

      expect(delivered_entries[0]["value"]).to eq(value)
    end

    it "delivers strings written to the device as info lines" do
      http.write("written to the device\n")
      ::Logger.new(http).warn("logged by a plain Ruby logger")

      entries = delivered_entries
      expect(entries.map { |entry| entry["level"] }).to eq(["info", "info"])
      expect(entries[0]["message"]).to eq("written to the device")
      expect(entries[1]["message"]).to end_with("WARN -- : logged by a plain Ruby logger")
    end
  end

  # Testing a private method because it helps break down our tests
  describe "#intervaled_flush" do
    it "should start a intervaled flush thread and flush on an interval" do
      http = described_class.new("MYKEY", flush_interval: 0.1)
      http.send(:ensure_flush_threads_are_started)
      expect(http).to receive(:flush_async).at_least(3).times
      sleep 1.1 # iterations check every 0.5 seconds
      http.close
    end
  end

  # Outlet
  describe "#request_outlet" do
    let(:time) { Time.utc(2016, 9, 1, 12, 0, 0) }

    it "should deliver requests on an interval" do
      stub = stub_request(:post, "https://in.logs.betterstack.com/").
        with do |request|
        decompressed_body = Zlib::Inflate.inflate(request.body)
        expect(decompressed_body).to start_with("\x92\x84\xA5level\xA4INFO\xA2dt\xBB2016-09-01T12:00:00.000000Z\xA7message\xB2test log message 1".force_encoding("ASCII-8BIT"))

        expect(request.headers['Authorization']).to eq('Bearer MYKEY')
        expect(request.headers['Content-Type']).to eq('application/msgpack')
        expect(request.headers['User-Agent']).to eq("Logtail Ruby/#{Logtail::VERSION} (HTTP)")

        true
      end.
        to_return(:status => 200, :body => "", :headers => {})

      http = described_class.new("MYKEY", flush_interval: 0.1)
      log_entry1 = Logtail::LogEntry.new("INFO", time, nil, "test log message 1", nil, nil)
      http.write(log_entry1)
      log_entry2 = Logtail::LogEntry.new("INFO", time, nil, "test log message 2", nil, nil)
      http.write(log_entry2)
      sleep 2

      expect(stub).to have_been_requested.times(1)

      http.close
    end

    context "when connecting or delivering fails" do
      # Raised from the stubs below to leave the outlet's endless loop. It is not a
      # StandardError, so the outlet's own `rescue => e` lets it through.
      let(:stop_outlet) { Class.new(Exception) }
      let(:http_device) { described_class.new("MYKEY", flush_continuously: false, requests_per_conn: 1) }
      let(:request_queue) { http_device.instance_variable_get(:@request_queue) }
      let(:waits) { [] }

      before do
        allow(http_device).to receive(:sleep) { |seconds| waits << seconds }
      end

      it "waits before reconnecting, twice as long after every refused connection, up to 30 seconds" do
        connection_attempts = 0
        allow_any_instance_of(Net::HTTP).to receive(:start) do
          connection_attempts += 1
          raise stop_outlet if connection_attempts > 7
          raise Errno::ECONNREFUSED
        end

        expect { http_device.send(:request_outlet) }.to raise_error(stop_outlet)
        expect(waits).to eq([1, 2, 4, 8, 16, 30, 30])
      end

      it "waits the same way when a request fails on an open connection, and still drops it after 3 attempts" do
        request_queue.enq(Logtail::LogDevices::HTTP::RequestAttempt.new(Net::HTTP::Post.new("/")))
        request_attempts = 0
        allow_any_instance_of(Net::HTTP).to receive(:request) do
          request_attempts += 1
          raise Errno::ECONNRESET
        end
        allow(http_device).to receive(:sleep) do |seconds|
          waits << seconds
          raise stop_outlet if waits.size == 3
        end

        expect { http_device.send(:request_outlet) }.to raise_error(stop_outlet)
        expect(waits).to eq([1, 2, 4])
        expect(request_attempts).to eq(3)
        expect(request_queue.size).to eq(0)
      end

      it "starts over at 1 second once a request is delivered" do
        request_queue.enq(Logtail::LogDevices::HTTP::RequestAttempt.new(Net::HTTP::Post.new("/")))
        connection = double("connection", request: double("response", code: "202"))
        connections = [:refused, :refused, :delivers, :refused, :refused]
        allow_any_instance_of(Net::HTTP).to receive(:start) do |_http, &block|
          case connections.shift
          when :refused then raise Errno::ECONNREFUSED
          when :delivers then block.call(connection)
          else raise stop_outlet
          end
        end

        expect { http_device.send(:request_outlet) }.to raise_error(stop_outlet)
        expect(waits).to eq([1, 2, 1, 2])
      end
    end

    it "lets close stop the outlet while it waits to reconnect" do
      connection_attempts = 0
      allow_any_instance_of(Net::HTTP).to receive(:start) do
        connection_attempts += 1
        raise Errno::ECONNREFUSED
      end
      http_device = described_class.new("MYKEY")
      http_device.send(:ensure_flush_threads_are_started)
      outlet = http_device.instance_variable_get(:@request_outlet_thread)
      # Up to 5 seconds for the thread's first attempt, which is slow on a cold TruffleRuby.
      500.times do
        break if connection_attempts > 0 && outlet.status == "sleep"
        sleep 0.01
      end

      closing = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      http_device.close
      expect(Process.clock_gettime(Process::CLOCK_MONOTONIC) - closing).to be < 0.5
      expect(outlet).not_to be_alive
      expect(connection_attempts).to eq(1)
    end
  end

  describe "#deliver_requests" do
    it "should handle exceptions properly and return" do
      allow_any_instance_of(Net::HTTP).to receive(:request).and_raise("boom")

      http_device = described_class.new("MYKEY", flush_continuously: false)
      req_queue = http_device.instance_variable_get(:@request_queue)

      # Place a request on the queue
      request = Net::HTTP::Post.new("/")
      request_attempt = Logtail::LogDevices::HTTP::RequestAttempt.new(request)
      request_attempt.attempted!
      req_queue.enq(request_attempt)

      # Start a HTTP connection to test the method directly
      http = http_device.send(:build_http)
      http.start do |conn|
        result = http_device.send(:deliver_requests, conn)
        expect(result).to eq(false)
      end

      expect(req_queue.size).to eq(1)

      # Start a HTTP connection to test the method directly
      http = http_device.send(:build_http)
      http.start do |conn|
        result = http_device.send(:deliver_requests, conn)
        expect(result).to eq(false)
      end

      # Ensure the request gets discards after 3 attempts
      expect(req_queue.size).to eq(0)
    end
  end
end