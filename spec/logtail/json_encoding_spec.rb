require "spec_helper"
require "open3"

# With json 3, ActiveSupport 8.0 and older break `to_json` called directly: ActiveSupport's
# encoder passes `quirks_mode:` to JSON.generate, and json 3 raises on the unknown keyword.
# Calls made by JSON.generate itself pass a JSON::State and keep working. The stub does the same
# for the Hashes and Arrays the gem encodes (TruffleRuby can't stub it on frozen String keys).
describe "JSON encoding when to_json raises like json 3 under ActiveSupport 8.0" do
  let(:time) { Time.utc(2016, 9, 1, 12, 0, 0) }
  let(:io) { StringIO.new }
  let(:logger) { Logtail::Logger.new(io) }

  before(:each) do
    [Hash, Array].each do |klass|
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

# ActiveSupport changes how the whole process encodes JSON, so these examples load it in another
# process. It prints a log entry encoded by ActiveSupport's encoder, as LogEntry#to_json did
# before, then by LogEntry#to_json and the JSONFormatter while that encoder raises, as it does
# with json 3 on ActiveSupport 8.0 and older.
describe "JSON encoding with ActiveSupport loaded" do
  def encode_with_active_support(fields)
    script = <<~RUBY
      require "logger" # ActiveSupport 6.1 needs it loaded first since concurrent-ruby 1.3.5
      require "active_support"
      require "active_support/core_ext/object/json"
      require "logtail"

      fields = #{fields}
      log_entry = Logtail::LogEntry.new("INFO", Time.utc(2016, 9, 1, 12), nil, "log message", nil, fields)
      puts ActiveSupport::JSON.encode(log_entry.to_hash)

      ActiveSupport::JSON.singleton_class.prepend(Module.new do
        def encode(*)
          raise ArgumentError, "unknown keyword: quirks_mode"
        end
      end)
      puts log_entry.to_json
      logger = Logtail::Logger.new($stdout)
      logger.formatter = Logtail::Logger::JSONFormatter.new
      logger.info("log message", fields)
    RUBY
    lib = File.expand_path("../../lib", __dir__)
    output, error, status = Open3.capture3(RbConfig.ruby, "-rbundler/setup", "-I", lib, "-e", script)
    expect(status.success?).to be(true), error
    output.lines.map { |line| JSON.parse(line) }
  end

  it "should encode times and symbols as ActiveSupport did" do
    encoded_by_active_support, encoded, logged = encode_with_active_support("{time: Time.utc(2026, 1, 2, 3, 4, 5), status: :active}")

    expect(encoded).to eq(encoded_by_active_support)
    expect(encoded).to include("time" => "2026-01-02T03:04:05.000Z", "status" => "active")
    expect(logged).to include("level" => "info", "time" => "2026-01-02T03:04:05.000Z", "status" => "active")
  end

  it "should encode NaN and Infinity as null, as ActiveSupport did" do
    encoded_by_active_support, encoded, logged = encode_with_active_support("{nan: Float::NAN, infinity: Float::INFINITY}")

    expect(encoded).to eq(encoded_by_active_support)
    expect(encoded).to include("nan" => nil, "infinity" => nil)
    expect(logged).to include("level" => "info", "nan" => nil, "infinity" => nil)
  end
end
