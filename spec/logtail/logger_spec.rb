require "spec_helper"

describe Logtail::Logger do
  describe "#initialize" do
    it "shoud select the augmented formatter" do
      logger = described_class.new(nil)
      expect(logger.formatter).to be_kind_of(Logtail::Logger::JSONFormatter)
    end

    context "development environment" do
      around(:each) do |example|
        old_env = Logtail::Config.instance.environment
        Logtail::Config.instance.environment = "development"
        example.run
        Logtail::Config.instance.environment = old_env
      end

      it "shoud select the message only formatter" do
        logger = described_class.new(nil)
        expect(logger.formatter).to be_kind_of(Logtail::Logger::MessageOnlyFormatter)
      end
    end

    it "should allow multiple io devices" do
      io1 = StringIO.new
      io2 = StringIO.new
      logger = Logtail::Logger.new(io1, io2)
      logger.info("hello world")
      expect(io1.string).to include("hello world")
      expect(io2.string).to include("hello world")
    end

    it "should allow multiple io devices and loggers" do
      io1 = StringIO.new
      io2 = StringIO.new
      io3 = StringIO.new
      extra_logger = ::Logger.new(io3)
      logger = Logtail::Logger.new(io1, io2, extra_logger)
      logger.info("hello world")
      expect(io1.string).to include("hello world")
      expect(io2.string).to include("hello world")
      expect(io3.string).to end_with("hello world\n")
    end
  end

  describe "#add" do
    let(:time) { Time.utc(2016, 9, 1, 12, 0, 0) }
    let(:io) { StringIO.new }
    let(:logger) { Logtail::Logger.new(io) }

    around(:each) do |example|
      Timecop.freeze(time) { example.run }
    end

    it "should respect the level via Logger constants" do
      logger.formatter = Logtail::Logger::MessageOnlyFormatter.new

      logger.level = ::Logger::DEBUG
      logger.info("message")
      expect(io.string).to eq("message\n")

      io.string = ""
      logger.level = ::Logger::WARN
      logger.info("message")
      expect(io.string).to eq("")
    end

    it "should respect the level via level symbols" do
      logger.formatter = Logtail::Logger::MessageOnlyFormatter.new

      logger.level = :debug
      logger.info("message")
      expect(io.string).to eq("message\n")

      io.string = ""
      logger.level = :warn
      logger.info("message")
      expect(io.string).to eq("")
    end

    context "with the AugmentedFormatter" do
      before(:each) { logger.formatter = Logtail::Logger::AugmentedFormatter.new }

      it "should accept strings" do
        logger.info("this is a test")
        expect(io.string).to start_with("this is a test @metadata {\"level\":\"info\",\"dt\":\"2016-09-01T12:00:00.000000Z\"")
      end

      it "should accept non-strings" do
        logger.info(true)
        expect(io.string).to include("true")
      end

      context "with a context" do
        let(:http_context) do
          Logtail::Contexts::HTTP.new(
            method: "POST",
            path: "/checkout",
            remote_addr: "123.456.789.10",
            request_id: "abcd1234"
          )
        end

        before(:each) do |example|
          Logtail::CurrentContext.add(http_context)
        end
        after(:each) do |example|
          Logtail::CurrentContext.remove(:http)
        end

        it "should snapshot and include the context" do
          expect(Logtail::CurrentContext.instance).to receive(:snapshot).and_call_original
          logger.info("this is a test")
          expect(io.string).to start_with("this is a test @metadata {\"level\":\"info\",\"dt\":\"2016-09-01T12:00:00.000000Z\"")
          expect(io.string).to include("\"http\":{\"method\":\"POST\",\"path\":\"/checkout\",\"remote_addr\":\"123.456.789.10\",\"request_id\":\"abcd1234\"}")
        end
      end

      it "should pass hash as metadata" do
        message = {message: "payment rejected", payment_rejected: {customer_id: "abcde1234", amount: 100}}
        logger.info(message)
        expect(io.string).to start_with("payment rejected @metadata {\"level\":\"info\",\"dt\":\"2016-09-01T12:00:00.000000Z\",")
        expect(io.string).to include("\"payment_rejected\":{\"customer_id\":\"abcde1234\",\"amount\":100}")
      end

      it "should allow :tag" do
        logger.info("event complete", tag: "tag1")
        expect(io.string).to include("\"tags\":[\"tag1\"]")
      end

      it "should allow :tags" do
        tags = ["tag1", "tag2"]
        logger.info("event complete", tags: tags)
        expect(io.string).to include("\"tags\":[\"tag1\",\"tag2\"]")

        # Ensure the tags object is not modified
        expect(tags).to eq(["tag1", "tag2"])
      end

      it "should allow functions" do
        logger.info do
          {message: "payment rejected", payment_rejected: {customer_id: "abcde1234", amount: 100}}
        end
        expect(io.string).to start_with("payment rejected @metadata {\"level\":\"info\",\"dt\":\"2016-09-01T12:00:00.000000Z\",")
        expect(io.string).to include("\"payment_rejected\":{\"customer_id\":\"abcde1234\",\"amount\":100}")
      end

      it "should escape new lines" do
        logger.info "first\nsecond"
        expect(io.string).to start_with("first\\nsecond @metadata")
      end
    end

    context "with the JSONFormatter" do
      before(:each) { logger.formatter = Logtail::Logger::JSONFormatter.new }

      it "should log in the correct format" do
        logger.info("this is a test")
        expect(io.string).to start_with("{\"level\":\"info\",\"dt\":\"2016-09-01T12:00:00.000000Z\",\"message\":\"this is a test\"")
      end
    end

    context "with the HTTP log device" do
      let(:io) { Logtail::LogDevices::HTTP.new("my_source_token") }

      it "should use the PassThroughFormatter" do
        expect(logger.formatter).to be_kind_of(Logtail::Logger::PassThroughFormatter)
      end
    end
  end

  describe "#error" do
    let(:io) { StringIO.new }
    let(:logger) { Logtail::Logger.new(io) }

    it "should allow default usage" do
      logger.error("log message")
      expect(io.string).to include("log message")
      expect(io.string).to include('"level":"error"')
    end

    it "should allow messages with options" do
      logger.error("log message", tag: "tag")
      expect(io.string).to include("log message")
      expect(io.string).to include('"level":"error"')
      expect(io.string).to include('"tags":["tag"]')
    end
  end

  describe "#formatter=" do
    it "should not allow changing the formatter when the device is HTTP" do
      http_device = Logtail::LogDevices::HTTP.new("source_token")
      logger = Logtail::Logger.new(http_device)
      expect { logger.formatter = ::Logger::Formatter.new }.to raise_error(ArgumentError)
    end

    it "should set the formatter" do
      logger = Logtail::Logger.new(STDOUT)
      formatter = ::Logger::Formatter.new
      logger.formatter = formatter
      expect(logger.formatter).to eq(formatter)
    end
  end

  describe "#info" do
    let(:io) { StringIO.new }
    let(:logger) { Logtail::Logger.new(io) }

    it "should allow default usage" do
      logger.info("log message")
      expect(io.string).to include("log message")
      expect(io.string).to include('"level":"info"')
    end

    it "should allow messages with options" do
      logger.info("log message", tag: "tag")
      expect(io.string).to include("log message")
      expect(io.string).to include('"level":"info"')
      expect(io.string).to include('"tags":["tag"]')
    end

    it "should accept non-string messages" do
      logger.info(true)
      expect(io.string).to include("true")
    end
  end
end
