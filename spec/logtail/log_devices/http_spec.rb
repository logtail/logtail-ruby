require "spec_helper"

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
      expect(msg_queue.flush).to eq(["test log message"])
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

    it "delivers in the calling thread when no outlet thread runs" do
      messages = []
      stub = stub_request(:post, "https://in.logs.betterstack.com/").to_return do |request|
        messages.concat(MessagePack.unpack(Zlib::Inflate.inflate(request.body)).map { |line| line["message"] })
        { status: 202 }
      end
      http = described_class.new("MYKEY", flush_continuously: false)
      http.write(Logtail::LogEntry.new("INFO", time, nil, "test log message 1", nil, nil))
      http.write(Logtail::LogEntry.new("INFO", time, nil, "test log message 2", nil, nil))

      http.flush

      expect(stub).to have_been_requested.once
      expect(messages).to eq(["test log message 1", "test log message 2"])
      http.close
    end

    it "waits about 5 seconds at most for the outlet thread to deliver" do
      allow_any_instance_of(Net::HTTP).to receive(:request) { sleep } # Better Stack never answers
      http = described_class.new("MYKEY")
      http.write(Logtail::LogEntry.new("INFO", time, nil, "test log message", nil, nil))

      flushing = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      http.flush
      expect(Process.clock_gettime(Process::CLOCK_MONOTONIC) - flushing).to be_between(4, 7)

      http.instance_variable_get(:@flush_thread).kill.join
      http.instance_variable_get(:@request_outlet_thread).kill.join
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