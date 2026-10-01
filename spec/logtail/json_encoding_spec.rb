require "spec_helper"

# With json 3, ActiveSupport 8.0 and older break `to_json` called directly: ActiveSupport's
# encoder passes `quirks_mode:` to JSON.generate, and json 3 raises on the unknown keyword.
# Calls made by JSON.generate itself pass a JSON::State and keep working. The stub does the same.
describe "JSON encoding when to_json raises like json 3 under ActiveSupport 8.0" do
  let(:time) { Time.utc(2016, 9, 1, 12, 0, 0) }
  let(:io) { StringIO.new }
  let(:logger) { Logtail::Logger.new(io) }

  before(:each) do
    [Hash, Array, String].each do |klass|
      allow_any_instance_of(klass).to receive(:to_json).and_wrap_original do |original, *args|
        raise ArgumentError, "unknown keyword: :quirks_mode" unless args.first.is_a?(::JSON::State)
        original.call(*args)
      end
    end
  end

  around(:each) do |example|
    Timecop.freeze(time) { example.run }
  end

  it "should log with the JSONFormatter" do
    logger.formatter = Logtail::Logger::JSONFormatter.new
    logger.info("log message", payment: {amount: 100, tags: ["a"]})

    line = JSON.parse(io.string)
    expect(line).to include("level" => "info", "dt" => "2016-09-01T12:00:00.000000Z", "message" => "log message")
    expect(line["payment"]).to eq("amount" => 100, "tags" => ["a"])
  end

  it "should log with the AugmentedFormatter" do
    logger.formatter = Logtail::Logger::AugmentedFormatter.new
    logger.info("log message", payment: {amount: 100})

    expect(io.string).to start_with("log message @metadata {\"level\":\"info\",\"dt\":\"2016-09-01T12:00:00.000000Z\"")
    expect(io.string).to include("\"payment\":{\"amount\":100}")
  end

  it "should encode a log entry" do
    log_entry = Logtail::LogEntry.new("INFO", time, nil, "log message", {custom: {a: "b"}}, nil)

    expect(JSON.parse(log_entry.to_json)).to include("level" => "INFO", "message" => "log message", "context" => {"custom" => {"a" => "b"}, "runtime" => {}})
  end

  it "should encode an event" do
    event = Logtail::Event.new("log message", {payment: {amount: 100}})

    expect(event.to_json).to eq("{\"payment\":{\"amount\":100}}")
  end

  it "should encode the backtrace of an error event" do
    event = Logtail::Events::Error.new(name: "RuntimeError", error_message: "Boom", backtrace: ["/path/to/file1.rb:26:in `function1'"])

    expect(event.backtrace_json).to eq("[\"/path/to/file1.rb:26:in `function1'\"]")
  end

  it "should encode the params of a controller call event" do
    event = Logtail::Events::ControllerCall.new(controller: "OrdersController", action: "show", params: {"id" => "1"})

    expect(event.params_json).to eq("{\"id\":\"1\"}")
  end

  it "should encode values added with json_encode" do
    hash = Logtail::Util::NonNilHashBuilder.build { |h| h.add(:headers_json, {"Accept" => "*/*"}, json_encode: true) }

    expect(hash).to eq(headers_json: "{\"Accept\":\"*/*\"}")
  end
end
