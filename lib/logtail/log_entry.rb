require "socket"
require "time"
require "pathname"

require "logtail/contexts"
require "logtail/events"

module Logtail
  # Represents a new log entry into the log. This is an intermediary class between
  # `Logger` and the log device that you set it up with.
  class LogEntry #:nodoc:
    BINARY_LIMIT_THRESHOLD = 1_000.freeze
    DT_PRECISION = 6.freeze
    MESSAGE_MAX_BYTES = 8192.freeze
    LOGGER_FILE = '/logtail/logger.rb'.freeze

    attr_reader :context_snapshot, :event, :level, :message, :progname, :tags, :time

    # Creates a log entry suitable to be sent to the Better Stack Telemetry API.
    # @param level [Integer] the log level / severity
    # @param time [Time] the exact time the log message was written
    # @param progname [String] the progname scope for the log message
    # @param message [String] Human readable log message.
    # @param context_snapshot [Hash] structured data representing a snapshot of the context at
    #   the given point in time.
    # @param event [Logtail.Event] structured data representing the log line event. This should be
    #   an instance of {Logtail.Event}.
    # @return [LogEntry] the resulting LogEntry object
    def initialize(level, time, progname, message, context_snapshot, event, options = {})
      @level = level
      @time = time.utc
      @progname = progname

      # If the message is not a string we call inspect to ensure it is a string.
      # This follows the default behavior set by ::Logger
      # See: https://github.com/ruby/ruby/blob/trunk/lib/logger.rb#L615
      @message = message.is_a?(String) ? message : message.inspect
      @message = @message.byteslice(0, MESSAGE_MAX_BYTES)
      @tags = options[:tags]
      @context_snapshot = context_snapshot
      @event = event
      @runtime_context = current_runtime_context || {}
    end

    # Builds a hash representation containing simple objects, suitable for serialization (JSON).
    def to_hash(options = {})
      hash = compute_log_hash(options)

      return hash unless defined?(ActiveSupport::ParameterFilter)

      parameter_filter = ActiveSupport::ParameterFilter.new(Rails.application.config.filter_parameters)
      parameter_filter.filter(hash)
    end

    def inspect
      to_s
    end

    def to_json(options = {})
      to_hash.to_json
    end

    def to_msgpack(*args)
      to_hash.to_msgpack(*args)
    end

    # This is used when LogEntry objects make it to a non-Logtail logger.
    def to_s
      message + "\n"
    end

    private

    def compute_log_hash(options)
      hash = {
        :level => level,
        :dt => formatted_dt,
        :message => sanitized_message,
      }

      if !tags.nil? && tags.length > 0
        hash[:tags] = tags
      end

      if !event.nil?
        hash.merge!(event)
      end

      if !context_snapshot.nil? && context_snapshot.length > 0
        hash[:context] = context_snapshot
      end

      hash[:context] ||= {}

      apply_options(hash, options)
    end

    def sanitized_message
      return "[omitted]" if internal_web? && parameters_message?

      message
    end

    def internal_web?
      ENV['INTERNAL_WEB'].present?
    end

    def parameters_message?
      return false if message.size < 100
      message.starts_with? "Parameters:"
    end

    def apply_options(hash, options)
      if options[:only]
        return hash.select do |key, _value|
          options[:only].include?(key)
        end
      end

      if options[:except]
        return hash.select do |key, _value|
          !options[:except].include?(key)
        end
      end

      hash
    end

    def formatted_dt
      @formatted_dt ||= time.iso8601(DT_PRECISION)
    end

    # Attempts to encode a non UTF-8 string into UTF-8, discarding invalid characters.
    # If it fails, a nil is returned.
    def encode_string(string)
      string.encode('UTF-8', {
        :invalid => :replace,
        :undef   => :replace,
        :replace => '?'
      })
    rescue Exception
      nil
    end

    def current_runtime_context
      last_logger_invocation_index = caller_locations.rindex { |frame| logtail_logger_frame?(frame) }
      return {} if last_logger_invocation_index.nil?

      calling_frame_index = last_logger_invocation_index + 1
      frame = caller_locations[calling_frame_index]
      return {} if frame.nil?

      return convert_to_runtime_context(frame)
    end

    def convert_to_runtime_context(frame)
      {
        file: path_relative_to_app_root(frame),
        line: frame.lineno,
        frame_label: frame.label.dup.force_encoding('UTF-8'),
      }
    end

    def logtail_logger_frame?(frame)
      !frame.path.nil? && frame.path.end_with?(LOGGER_FILE)
    end

    def path_relative_to_app_root(frame)
      Pathname.new(frame.absolute_path).relative_path_from(root_path).to_s
    rescue
      frame.absolute_path || frame.path
    end

    def root_path
      if Object.const_defined?('Rails')
        Rails.root
      elsif Object.const_defined?('Rack::Directory')
        Pathname.new(Rack::Directory.new('').root)
      else
        base_file = caller_locations.last.absolute_path
        Pathname.new(File.dirname(base_file || '/'))
      end
    end
  end
end
