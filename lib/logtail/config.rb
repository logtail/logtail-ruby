require "logger"
require "singleton"

require 'logtail/config/middlewares'
require 'logtail/config/integrations'

module Logtail
  # Singleton class for reading and setting Logtail configuration.
  #
  # For Rails apps, this is installed into `config.logtail`. See examples below.
  #
  # @example Rails example
  #   config.logtail.append_metadata = false
  # @example Everything else
  #   config = Logtail::Config.instance
  #   config.append_metdata = false
  class Config
    # @private
    class NoLoggerError < StandardError; end

    # @private
    class SimpleLogFormatter < ::Logger::Formatter
      # This method is invoked when a log event occurs
      def call(severity, timestamp, progname, msg)
        "[Logtail] #{String === msg ? msg : msg.inspect}\n"
      end
    end

    DEVELOPMENT_NAME = "development".freeze
    PRODUCTION_NAME = "production".freeze
    STAGING_NAME = "staging".freeze
    TEST_NAME = "test".freeze

    include Singleton

    attr_writer :http_body_limit

    # Whether a particular {Logtail::LogEntry} should be sent to Better Stack
    def send_to_better_stack?(log_entry)
      !@better_stack_filters&.any? { |blocker| blocker.call(log_entry) }
    rescue => e
      debug { "Could not determine whether to send LogEntry to Better Stack (assumed yes): #{e}" }
      true
    end

    # This allows filtering logs that are sent to Better Stack. Can be called multiple times, all filters will
    # be applied. If the passed block RETURNS TRUE for a particular LogEntry, it WILL NOT BE SENT to Better Stack.
    #
    # See {Logtail::LogEntry} for available attributes of the block parameter.
    #
    # @example Rails
    #   config.logtail.filter_sent_to_better_stack { |log_entry| log_entry.context_snapshot[:http][:path].start_with?('/_') }
    # @example Everything else
    #   Logtail.config.filter_sent_to_better_stack { |log_entry| log_entry.message.include?('IGNORE') }
    def filter_sent_to_better_stack(&block)
      @better_stack_filters ||= []
      @better_stack_filters << -> (log_entry) { yield(log_entry) }
    end

    # Convenience method for logging debug statements to the debug logger
    # set in this class.
    # @private
    def debug(&block)
      debug_logger = Config.instance.debug_logger
      if debug_logger
        message = yield
        debug_logger.debug(message)
      end
      true
    end

    # This is useful for debugging. This Sets a debug_logger to view internal Logtail library
    # log messages. The default is `nil`. Meaning log to nothing.
    #
    # See {#debug_to_file!} and {#debug_to_stdout!} for convenience methods that handle creating
    # and setting the logger.
    #
    # @example Rails
    #   config.logtail.debug_logger = ::Logger.new(STDOUT)
    # @example Everything else
    #   Logtail::Config.instance.debug_logger = ::Logger.new(STDOUT)
    def debug_logger=(value)
      @debug_logger = value
    end

    # Accessor method for {#debug_logger=}.
    def debug_logger
      @debug_logger
    end

    # A convenience method for writing internal Logtail debug messages to a file.
    #
    # @example Rails
    #   config.Logtail.debug_to_file!("#{Rails.root}/log/logtail.log")
    # @example Everything else
    #   Logtail::Config.instance.debug_to_file!("log/logtail.log")
    def debug_to_file!(file_path)
      FileUtils.mkdir_p( File.dirname(file_path) )
      file = File.open(file_path, "ab")
      file_logger = ::Logger.new(file)
      file_logger.formatter = SimpleLogFormatter.new
      self.debug_logger = file_logger
    end

    # A convenience method for writing internal Logtail debug messages to STDOUT.
    #
    # @example Rails
    #   config.logtail.debug_to_stdout!
    # @example Everything else
    #   Logtail::Config.instance.debug_to_stdout!
    def debug_to_stdout!
      stdout_logger = ::Logger.new(STDOUT)
      stdout_logger.formatter = SimpleLogFormatter.new
      self.debug_logger = stdout_logger
    end

    # The environment your app is running in. Defaults to `RACK_ENV` and `RAILS_ENV`.
    # It should be rare that you have to set this. If the aforementioned env vars are not
    # set please do.
    #
    # @example If you do not set `RACK_ENV` or `RAILS_ENV`
    #   Logtail::Config.instance.environment = "staging"
    def environment=(value)
      @environment = value
    end

    # Accessor method for {#environment=}
    def environment
      @environment ||= ENV["RACK_ENV"] || ENV["RAILS_ENV"] || "development"
    end

    def integrations
      Config::Integrations
    end

    def middlewares
      Config::Middlewares
    end

    # This is the _main_ logger Logtail writes to. All of the Logtail integrations write to
    # this logger instance. It should be set to your global logger. For Rails, this is set
    # automatically to `Rails.logger`, you should not have to set this.
    #
    # @example Non-rails frameworks
    #   my_global_logger = Logtail::Logger.new(STDOUT)
    #   Logtail::Config.instance.logger = my_global_logger
    def logger=(value)
      @logger = value
    end

    # Accessor method for {#logger=}.
    def logger
      if @logger.is_a?(Proc)
        @logger.call()
      else
        @logger ||= Logger.new(STDOUT)
      end
    end

    # @private
    def development?
      environment == DEVELOPMENT_NAME
    end

    # @private
    def test?
      environment == TEST_NAME
    end

    # @private
    def production?
      environment == PRODUCTION_NAME
    end

    # @private
    def staging?
      environment == STAGING_NAME
    end
  end
end
