require "spec_helper"

describe Logtail::LogEntry do
  let(:time) { Time.utc(2021, 06, 11, 12, 0, 0) }

  describe "#to_msgpack" do
    it "should encode properly with an event and context" do
      event = {
        message: "event_message",
        event: {
          event_type: {
            a: 1
          }
        }
      }
      context = {custom: {a: "b"}}
      log_entry = described_class.new("INFO", time, nil, "log message", context, event)
      msgpack = log_entry.to_msgpack
      expect(msgpack).to start_with("\x85\xA5level\xA4INFO\xA2dt\xBB2021-06-11T12:00:00.000000Z".force_encoding("ASCII-8BIT"))
    end
  end

  describe "#to_hash" do
    it "should include runtime context information" do
      log_entry = Logtail::Logger::PassThroughFormatter.new.call("INFO", time, "", "log message")

      hash = log_entry.to_hash
      expect(hash[:context]).to_not be_nil
      expect(hash[:context][:runtime]).to_not be_nil
      expect(hash[:context][:runtime][:file]).to end_with('/spec/logtail/log_entry_spec.rb')
      expect(hash[:context][:runtime][:line]).to be(25)
      expect(hash[:context][:runtime][:frame_label]).to_not be_nil
      expect(hash[:context][:runtime][:frame_label].encoding.to_s).to eq('UTF-8')
    end

    context "with a context logged by the user" do
      let(:context_snapshot) { {system: {hostname: "computer-name", pid: 123}, runtime: {thread_id: 456}} }

      it "should keep the user's context next to the system and runtime context" do
        log_entry = described_class.new("INFO", time, nil, "log message", context_snapshot, {context: {tenant: 1}})

        context = log_entry.to_hash[:context]
        expect(context[:tenant]).to eq(1)
        expect(context[:system]).to eq(hostname: "computer-name", pid: 123)
        expect(context[:runtime]).to eq(thread_id: 456)
      end

      it "should merge nested hashes, keeping the gem's own values on conflict" do
        user_context = {system: {hostname: "spoofed", region: "eu-west"}, runtime: {worker: "w1"}, job: {id: 7}}
        log_entry = described_class.new("INFO", time, nil, "log message", context_snapshot, {context: user_context})

        context = log_entry.to_hash[:context]
        expect(context[:system]).to eq(hostname: "computer-name", pid: 123, region: "eu-west")
        expect(context[:runtime]).to eq(thread_id: 456, worker: "w1")
        expect(context[:job]).to eq(id: 7)
      end

      it "should not modify the user's context or the current context" do
        user_context = {runtime: {worker: "w1"}}
        Logtail::CurrentContext.with(runtime: {thread_id: 456}) do
          log_entry = Logtail::Logger::PassThroughFormatter.new.call("INFO", time, "", {message: "log message", context: user_context})

          runtime_context = log_entry.to_hash[:context][:runtime]
          expect(runtime_context).to include(thread_id: 456, worker: "w1")
          expect(runtime_context[:file]).to end_with('/spec/logtail/log_entry_spec.rb')
          expect(user_context).to eq(runtime: {worker: "w1"})
          expect(Logtail::CurrentContext.instance.snapshot[:runtime]).to eq(thread_id: 456)
        end
      end

      it "should ignore a context that isn't a Hash" do
        log_entry = described_class.new("INFO", time, nil, "log message", context_snapshot, {context: "checkout"})
        expect(log_entry.to_hash[:context]).to eq(context_snapshot)

        log_entry = described_class.new("INFO", time, nil, "log message", nil, {context: "checkout"})
        expect(log_entry.to_hash[:context]).to eq(runtime: {})
      end

      # logtail-rails logs Rails.event events this way, with the context set by Rails.event.set_context
      it "should deliver the context of an event" do
        http_device = Logtail::LogDevices::HTTP.new("MYKEY", flush_continuously: false)
        logger = Logtail::Logger.new(http_device)
        Logtail::CurrentContext.with(system: {hostname: "computer-name.domain.com", pid: 123}) do
          logger.info("[order.placed] id=1", event_name: "order.placed", payload: {id: 1},
                      context: {request_id: "abc-123", shop_id: 42}, tags: [], source_location: {})
        end

        http_device.send(:flush_async)
        request = http_device.instance_variable_get(:@request_queue).deq.request
        delivered = MessagePack.unpack(Zlib::Inflate.inflate(request.body)).first
        expect(delivered["event_name"]).to eq("order.placed")
        expect(delivered["context"]).to include("request_id" => "abc-123", "shop_id" => 42)
        expect(delivered["context"]["system"]).to eq("hostname" => "computer-name.domain.com", "pid" => 123)
        expect(delivered["context"]["runtime"]).to include("file", "line")
      end
    end
  end

  describe "#message" do
    it "cuts a long message on a character boundary" do
      # The 4-byte emoji takes bytes 8,191 to 8,194, across the 8,192-byte limit.
      message = "a" * 8190 + "\u{1F600} and more"
      log_entry = described_class.new("INFO", time, nil, message, nil, nil)

      expect(log_entry.message.bytesize).to eq(8190)
      expect(log_entry.message.valid_encoding?).to be(true)
    end
  end
end
