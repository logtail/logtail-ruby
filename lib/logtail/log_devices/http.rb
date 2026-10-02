require "msgpack"
require "net/https"
require "set"
require "time"
require "zlib"

require "logtail/config"
require "logtail/log_devices/http/flushable_dropping_sized_queue"
require "logtail/log_devices/http/request_attempt"
require "logtail/version"

module Logtail
  module LogDevices
    # A highly efficient log device that buffers and delivers log messages over HTTPS to
    # the Logtail API. It uses batches, keep-alive connections, and msgpack to deliver logs with
    # high-throughput and little overhead. All log preparation and delivery is done asynchronously
    # in a thread as not to block application execution and efficiently deliver logs for
    # multi-threaded environments.
    #
    # See {#initialize} for options and more details.
    class HTTP
      DEFAULT_INGESTING_HOST = "in.logs.betterstack.com".freeze
      DEFAULT_INGESTING_PORT = 443
      DEFAULT_INGESTING_SCHEME = "https".freeze
      CONTENT_TYPE = "application/msgpack".freeze
      USER_AGENT = "Logtail Ruby/#{Logtail::VERSION} (HTTP)".freeze
      ENCODABLE_INTEGERS = (-2**63...2**64).freeze # the integers msgpack can encode
      MAX_UNTRACKED_DEPTH = 100 # nested hashes and arrays, see #encodable_value
      INITIAL_RECONNECT_WAIT = 1 # second
      MAX_RECONNECT_WAIT = 30 # seconds
      MAX_RETRY_AFTER = 60 # seconds
      # The HTTP statuses of rejected batches this process has warned about, see {#report_rejected_batch}.
      REPORTED_REJECTIONS = []
      REPORTED_REJECTIONS_LOCK = Mutex.new
      SYNCHRONOUS_DELIVERY_TIMEOUT = 5 # seconds, to connect and to read the response

      # Instantiates a new HTTP log device that can be passed to {Logtail::Logger#initialize}.
      #
      # The class maintains a buffer which is flushed in batches to the Logtail API. 2
      # options control when the flush happens, `:batch_byte_size` and `:flush_interval`.
      # If either of these are surpassed, the buffer will be flushed.
      #
      # By default, the buffer will drop log messages when the rate of log messages exceeds
      # the maximum delivery rate. You can change this with the `:request_queue` option.
      #
      # @param source_token [String] The API key provided to you after you add your source to
      #   [Better Stack](https://telemetry.betterstack.com).
      # @param [Hash] options the options to create a HTTP log device with.
      # @option attributes [Symbol] :batch_size (1000) Determines the maximum of log lines in
      #   each HTTP payload. If the queue exceeds this limit an HTTP request will be issued. Bigger
      #   payloads mean higher throughput, but also use more memory. Logtail will not accept
      #   payloads larger than 1mb.
      # @option attributes [Symbol] :flush_continuously (true) This should only be disabled under
      #   special circumstances (like test suites). Setting this to `false` disables the
      #   continuous flushing of log message. As a result, flushing must be handled externally
      #   via the #flush method.
      # @option attributes [Symbol] :flush_interval (1) How often the client should
      #   attempt to deliver logs to the Logtail API in fractional seconds. The HTTP client buffers
      #   logs and this options represents how often that will happen, assuming `:batch_byte_size`
      #   is not met.
      # @option attributes [Symbol] :requests_per_conn (2500) The number of requests to send over a
      #   single persistent connection. After this number is met, the connection will be closed
      #   and a new one will be opened.
      # @option attributes [Symbol] :request_queue (FlushableDroppingSizedQueue.new(25)) The request
      #   queue object that queues Net::HTTP requests for delivery. By default this is a
      #   `FlushableDroppingSizedQueue` of size `25`. Meaning once the queue fills up to 25
      #   requests new requests will be dropped. If you'd prefer to apply back pressure,
      #   ensuring you do not lose log data, pass a standard {SizedQueue}. See examples for
      #   an example.
      # @option attributes [Symbol] :ingesting_host The Better Stack Telemetry ingesting host to delivery the log lines to.
      #   The default is set via {INGESTING_HOST}.
      #
      # @example Basic usage
      #   Logtail::Logger.new(Logtail::LogDevices::HTTP.new("<source_token>", ingesting_host: "<ingesting_host>"))
      #
      # @example Apply back pressure instead of dropping messages
      #   http_log_device = Logtail::LogDevices::HTTP.new("<source_token>", ingesting_host: "<ingesting_host>", request_queue: SizedQueue.new(25))
      #   Logtail::Logger.new(http_log_device)
      def initialize(source_token, options = {})
        # Handle backward-compatibility of argument names
        options[:ingesting_host] ||= options[:logtail_host]
        options[:ingesting_port] ||= options[:logtail_port]
        options[:ingesting_scheme] ||= options[:logtail_scheme]

        @source_token = source_token || raise(ArgumentError.new("The source_token parameter cannot be blank"))
        @ingesting_host = options[:ingesting_host] || ENV['INGESTING_HOST'] || ENV['LOGTAIL_HOST'] || DEFAULT_INGESTING_HOST
        @ingesting_port = options[:ingesting_port] || ENV['INGESTING_PORT'] || ENV['LOGTAIL_PORT'] || DEFAULT_INGESTING_PORT
        @ingesting_scheme = options[:ingesting_scheme] || ENV['INGESTING_SCHEME'] || ENV['LOGTAIL_SCHEME'] || DEFAULT_INGESTING_SCHEME
        @batch_size = options[:batch_size] || 1_000
        @flush_continuously = options[:flush_continuously] != false
        @flush_interval = options[:flush_interval] || 2 # 2 seconds
        @requests_per_conn = options[:requests_per_conn] || 2_500
        # The process that owns the queues and threads, see {#reset_if_forked}
        @pid = Process.pid
        @fork_lock = Mutex.new
        @msg_queue = FlushableDroppingSizedQueue.new(@batch_size)
        @request_queue = options[:request_queue] || FlushableDroppingSizedQueue.new(25)
        @successive_error_count = 0
        @requests_in_flight = 0
        @last_resp = nil
        @reconnect_wait = INITIAL_RECONNECT_WAIT
        @closed = false
        @late_delivery_failed = false

        # Delivers what is still buffered when the process exits. One hook per device, however
        # many loggers write to it.
        at_exit { close }
      end

      # Write a new log line message to the buffer, and flush asynchronously if the
      # message queue is full. We flush asynchronously because the maximum message batch
      # size is constricted by the Logtail API. The actual application limit is a multiple
      # of this. Hence the `@request_queue`.
      def write(msg)
        # Strings, e.g. from a plain ::Logger writing to this device, are sent as info lines.
        msg = LogEntry.new(:info, Time.now, nil, msg.to_s.chomp, nil, nil) unless msg.is_a?(LogEntry)
        return unless Logtail.config.send_to_better_stack?(msg)
        reset_if_forked

        @msg_queue.enq(msg)
        # No thread delivers what is written after #close, e.g. by an at_exit hook that runs
        # after the device's own.
        return deliver_late_lines if @closed

        # Lazily start flush threads to ensure threads are alive after forking processes.
        # If the threads are started during instantiation they will not be copied when
        # the current process is forked. This is the case with various web servers,
        # such as phusion passenger.
        begin
          ensure_flush_threads_are_started
        rescue ThreadError
          # Ruby refuses new threads while it shuts down, e.g. to a thread that logs in an
          # `ensure` block as it is killed at exit.
          return deliver_late_lines
        end

        if @msg_queue.full?
          Logtail::Config.instance.debug { "Flushing HTTP buffer via write" }
          flush_async
        end
        true
      end

      # Flush all log messages in the buffer synchronously. This method will not return
      # until delivery of the messages has been successful, or about 5 seconds have passed.
      # When no outlet thread runs (`flush_continuously: false`, or a forked child that hasn't
      # logged yet), the messages are delivered in the calling thread. If you want to flush
      # asynchronously see {#flush_async}.
      def flush
        reset_if_forked
        flush_async
        if @request_outlet_thread && @request_outlet_thread.alive?
          wait_on_request_queue
        else
          deliver_synchronously(dequeue_requests)
        end
        true
      end

      # Closes the log device, cleans up, and attempts one last delivery. Closing it again does
      # nothing; lines written after it are delivered right away (see {#write}).
      def close
        reset_if_forked
        return if @closed
        @closed = true

        # Kill the flush thread immediately since we are about to flush again.
        @flush_thread.kill.join if @flush_thread

        # Flush all remaining messages
        flush

        # Kill the request queue thread. Flushing ensures that no requests are pending.
        @request_outlet_thread.kill.join if @request_outlet_thread
      end

      def deliver_one(msg)
        http = build_http

        begin
          resp = http.start do |conn|
            req = build_request([msg])
            @requests_in_flight += 1
            conn.request(req)
          end
          return resp
        rescue => e
          Logtail::Config.instance.debug { "error: #{e.message}" }
          return e
        ensure
          http.finish if http.started?
          @requests_in_flight -= 1
        end
      end

      def verify_delivery!
        5.times do |i|
          sleep(2)

          if @last_resp.nil?
            print "."
          elsif @last_resp.code == "202"
            puts "Log delivery successful! View your logs at https://telemetry.betterstack.com"
          else
            raise <<-MESSAGE

Log delivery failed!

Status: #{@last_resp.code}
Body: #{@last_resp.body}

You can enable internal Logtail debug logging with the following:

Logtail::Config.instance.debug_logger = ::Logger.new(STDOUT)
            MESSAGE
          end
        end

        raise <<-MESSAGE

Log delivery failed! No request was made.

You can enable internal debug logging with the following:

Logtail::Config.instance.debug_logger = ::Logger.new(STDOUT)
        MESSAGE
      end

      private
        # This is a convenience method to ensure the flush thread are
        # started. This is called lazily from {#write} so that we
        # only start the threads as needed, but it also ensures
        # threads are started after process forking.
        def ensure_flush_threads_are_started
          if @flush_continuously
            if @request_outlet_thread.nil? || !@request_outlet_thread.alive?
              @request_outlet_thread = Thread.new { request_outlet }
            end

            if @flush_thread.nil? || !@flush_thread.alive?
              @flush_thread = Thread.new { intervaled_flush }
            end
          end
        end

        # The queues and threads belong to the process that created them. After a fork, the
        # parent still delivers the lines it buffered, so a child that kept them would send them
        # again, and the parent's threads don't run in the child. The child starts over with
        # empty queues and starts its own threads once it logs, also when the parent closed the
        # device before forking.
        def reset_if_forked
          return if @pid == Process.pid

          @fork_lock.synchronize do
            return if @pid == Process.pid

            @msg_queue = FlushableDroppingSizedQueue.new(@batch_size)
            # The request queue can be a SizedQueue passed as the :request_queue option
            @request_queue.respond_to?(:flush) ? @request_queue.flush : @request_queue.clear
            @flush_thread = @request_outlet_thread = nil
            @requests_in_flight = 0
            @reconnect_wait = INITIAL_RECONNECT_WAIT
            @closed = @late_delivery_failed = false
            @pid = Process.pid
          end
        end

        # Takes the queued requests off the request queue, for {#flush} when no outlet thread
        # runs. It checks the size first because a SizedQueue (see :request_queue) blocks when empty.
        def dequeue_requests
          requests = []
          while @request_queue.size > 0 && (request_attempt = @request_queue.deq)
            requests << request_attempt
          end
          requests
        end

        # Builds an HTTP request based on the current messages queued.
        def build_request(msgs)
          path = '/'
          req = Net::HTTP::Post.new(path)
          req['Authorization'] = authorization_payload
          req['Content-Type'] = CONTENT_TYPE
          req['Content-Encoding'] = 'deflate'
          req['User-Agent'] = USER_AGENT
          # Entries are encoded one at a time, so one that can't be encoded doesn't lose the batch.
          packer = MessagePack::DefaultFactory.packer
          uncompressed = packer.write_array_header(msgs.size).to_s
          packer.reset
          msgs.each { |msg| uncompressed << encode_log_entry(msg, packer) }
          req.body = Zlib::Deflate.deflate(uncompressed, Zlib::BEST_SPEED)
          req
        end

        # Encodes a single log entry with msgpack, with the packer if given, which it leaves empty.
        # An entry that still can't be encoded is replaced by one that says why, with the same
        # level and time.
        def encode_log_entry(msg, packer = MessagePack::DefaultFactory.packer)
          packer.write(encodable_value(msg.to_hash)).to_s
        rescue StandardError, SystemStackError => e
          Logtail::Config.instance.debug { "Could not encode log entry: #{e.inspect}" }
          error = force_utf8_encoding("#{e.class}: #{e.message}")
          message = "Logtail could not encode this log line (#{error}): #{force_utf8_encoding(msg.message)}"
          {
            level: msg.level,
            dt: msg.time.iso8601(LogEntry::DT_PRECISION),
            message: message.byteslice(0, LogEntry::MESSAGE_MAX_BYTES).scrub(""),
          }.to_msgpack
        ensure
          packer.reset
        end

        # Converts what msgpack can't encode, recursively, mostly into strings, and passes strings
        # that aren't valid UTF-8 to {#force_utf8_encoding}. Returns the value itself when nothing
        # needs to change, as for most log lines, and otherwise copies only the hashes and arrays
        # that change. A hash or array that contains itself is cut off with "[circular]".
        def encodable_value(value)
          # The first pass doesn't keep track of the hashes and arrays it is in, and gives up when
          # they nest too deep, as in a cycle. The second pass keeps track of them to find cycles.
          catch(:too_deep) { return replacement_for(value, nil, 0) || value }
          replacement_for(value, {}.compare_by_identity, 0) || value
        end

        # Returns what to send instead of the value, or nil to send the value as it is.
        def replacement_for(value, parents, depth)
          case value
          when Hash
            hash_replacement(value, parents, depth)
          when String
            force_utf8_encoding(value) unless value.valid_encoding? && (value.encoding == Encoding::UTF_8 || value.encoding == Encoding::US_ASCII)
          when Integer
            value.to_s unless value.bit_length < 64 || ENCODABLE_INTEGERS.cover?(value)
          when nil, true, false, Symbol, Float
            nil
          when Array, Set, Struct
            if parents
              return "[circular]" if parents.key?(value)

              parents[value] = true
            elsif depth == MAX_UNTRACKED_DEPTH
              throw :too_deep
            end
            replacement =
              if value.is_a?(Array)
                array_replacement(value, parents, depth + 1)
              elsif value.is_a?(Set)
                array_replacement(items = value.to_a, parents, depth + 1) || items
              else
                hash_replacement(members = value.to_h, parents, depth + 1) || members
              end
            parents.delete(value) if parents
            replacement
          else
            force_utf8_encoding(converted_value(value))
          end
        end

        # Returns a copy of the hash with the replacements for its keys and values, or nil if none
        # needs one. The most common keys and values are checked right here, which is faster.
        def hash_replacement(hash, parents, depth)
          if parents
            return "[circular]" if parents.key?(hash)

            parents[hash] = true
          elsif depth == MAX_UNTRACKED_DEPTH
            throw :too_deep
          end
          copy = nil
          key_changes = false
          hash.each_pair do |key, item|
            new_key = replacement_for(key, parents, depth + 1) unless key.is_a?(Symbol)
            new_item =
              if item.is_a?(String)
                force_utf8_encoding(item) unless item.valid_encoding? && (item.encoding == Encoding::UTF_8 || item.encoding == Encoding::US_ASCII)
              elsif item.is_a?(Hash)
                hash_replacement(item, parents, depth + 1)
              elsif !(item.nil? || item.is_a?(Integer) && item.bit_length < 64 || item.is_a?(Symbol) || item.is_a?(Float))
                replacement_for(item, parents, depth + 1)
              end
            if new_key
              key_changes = true
              break
            elsif new_item
              (copy ||= Hash[hash])[key] = new_item
            end
          end
          # A key that changes is rare, the copy is then built from scratch to keep the order of the keys
          if key_changes
            copy = {}
            hash.each_pair { |key, item| copy[replacement_for(key, parents, depth + 1) || key] = replacement_for(item, parents, depth + 1) || item }
          end
          parents.delete(hash) if parents
          copy
        end

        # Returns a copy of the array with the replacements for its items, or nil if none needs one.
        def array_replacement(array, parents, depth)
          copy = nil
          array.each_with_index do |item, index|
            new_item = replacement_for(item, parents, depth)
            (copy ||= Array.new(array))[index] = new_item if new_item
          end
          copy
        end

        # Converts a value msgpack can't encode that isn't a hash, array, set or struct.
        def converted_value(value)
          case value
          when Time, DateTime # Rails makes ActiveSupport::TimeWithZone match Time too
            value.to_time.getutc.iso8601(LogEntry::DT_PRECISION)
          when Date
            value.iso8601
          when Exception
            { class: value.class.name, message: value.message }
          when Numeric
            # BigDecimal#to_s would use an exponent, "0.1999e2"
            defined?(::BigDecimal) && value.is_a?(::BigDecimal) ? value.to_s("F") : value.to_s
          else
            # The public id of a Rack::Session::SessionId is the cookie of a server-side session
            value.respond_to?(:private_id) ? value.private_id : value.to_s
          end
        end

        def force_utf8_encoding(data)
          if data.respond_to?(:force_encoding)
            # Only valid UTF-8 may leave: Better Stack stores anything else as invalid JSON. A string
            # that is valid UTF-8 already, as nearly all are, is sent as it is.
            return data if data.valid_encoding? && (data.encoding == Encoding::UTF_8 || data.encoding == Encoding::US_ASCII)

            case data.encoding
            when Encoding::UTF_8, Encoding::BINARY, Encoding::US_ASCII
              data.dup.force_encoding('UTF-8').scrub
            else
              begin
                data.encode('UTF-8', invalid: :replace, undef: :replace)
              rescue Encoding::ConverterNotFoundError
                data.dup.force_encoding('UTF-8').scrub
              end
            end
          elsif data.is_a?(Hash)
            data.each_with_object({}) { |(key, val), hash| hash[force_utf8_encoding(key)] = force_utf8_encoding(val) }
          elsif data.is_a?(Array)
            data.map { |val| force_utf8_encoding(val) }
          else
            data
          end
        end

        # Flushes the message buffer asynchronously. The reason we provide this
        # method is because the message buffer limit is constricted by the
        # Logtail API. The application limit is multiples of the buffer limit,
        # hence the `@request_queue`, allowing us to buffer beyond the Logtail API
        # imposed limit.
        def flush_async
          @last_async_flush = Time.now
          msgs = @msg_queue.flush
          return if msgs.empty?

          req = build_request(msgs)
          if !req.nil?
            Logtail::Config.instance.debug { "New request placed on queue" }
            request_attempt = RequestAttempt.new(req, msgs.size)
            @request_queue.enq(request_attempt)
          end
        end

        # Sends the requests in the calling thread, for when no outlet thread delivers them.
        # Returns whether all of them were delivered. A request answered with 408, 429 or 5xx isn't
        # retried, nothing would deliver the retry; one rejected with any other status that isn't
        # 2xx is reported like in {#deliver_requests}. Errors only go to the debug log, also those
        # that aren't StandardErrors (WebMock refuses to connect with one); signals are raised as usual.
        def deliver_synchronously(request_attempts)
          return true if request_attempts.empty?

          http = build_http
          http.open_timeout = http.read_timeout = SYNCHRONOUS_DELIVERY_TIMEOUT
          begin
            http.start
          rescue ThreadError
            # While Ruby shuts down it refuses new threads, and Net::HTTP (before Ruby 4.0) needs
            # one to time out connecting. Then it connects without a timeout, but only to a host
            # that has answered before.
            raise if @last_resp.nil?
            http.open_timeout = nil
            http.start
          end
          delivered = true
          request_attempts.each do |request_attempt|
            resp = @last_resp = http.request(request_attempt.request)
            next if resp.code.start_with?("2")

            delivered = false
            Logtail::Config.instance.debug { "Log delivery failed! status: #{resp.code}, body: #{resp.body}" }
            report_rejected_batch(request_attempt, resp) unless resp.code == "408" || resp.code == "429" || resp.code.start_with?("5")
          end
          delivered
        rescue SignalException
          raise
        rescue Exception => e
          Logtail::Config.instance.debug { "Synchronous delivery failed: #{e.message}" }
          false
        ensure
          http.finish if http && http.started?
        end

        # Waits on the request queue. This is used in {#flush} to ensure
        # the log data has been delivered before returning.
        def wait_on_request_queue
          # Wait 5 seconds
          10.times do |i|
            if @request_queue.size == 0 && @requests_in_flight == 0
              Logtail::Config.instance.debug { "Request queue is empty and no requests are in flight, finish waiting" }
              return true
            end
            if outlet_stalled?
              Logtail::Config.instance.debug { "The HTTP outlet can't deliver the requests, finish waiting" }
              return false
            end
            Logtail::Config.instance.debug do
              "Request size #{@request_queue.size}, reqs in-flight #{@requests_in_flight}, " \
                "continue waiting (iteration #{i + 1})"
            end
            sleep 0.5
          end
        end

        # Whether the outlet thread can't deliver anything while {#close} waits for it: the thread
        # is dead, or the host has never answered and the outlet has already waited to reconnect
        # after a failed connection (@reconnect_wait grows after each wait until a response).
        def outlet_stalled?
          return true unless @request_outlet_thread && @request_outlet_thread.alive?

          @last_resp.nil? && @reconnect_wait > INITIAL_RECONNECT_WAIT
        end

        # Delivers the buffered lines in the calling thread, for {#write} when no thread can. After
        # a delivery fails, e.g. to an unreachable host, later lines are dropped so they can't
        # hold up the exit one by one.
        def deliver_late_lines
          msgs = @msg_queue.flush
          return true if msgs.empty?

          if @late_delivery_failed
            Logtail::Config.instance.debug { "Dropping #{msgs.size} log lines, an earlier synchronous delivery failed" }
          else
            @late_delivery_failed = !deliver_synchronously([RequestAttempt.new(build_request(msgs), msgs.size)])
          end
          true
        end

        # Flushes the message queue on an interval. You will notice that {#write} also
        # flushes the buffer if it is full. This method takes note of this via the
        # `@last_async_flush` variable as to not flush immediately after a write flush.
        def intervaled_flush
          # Wait specified time period before starting
          sleep @flush_interval

          loop do
            begin
              if intervaled_flush_ready?
                Logtail::Config.instance.debug { "Flushing HTTP buffer via the interval" }
                flush_async
              end

              sleep(0.5)
            rescue Exception => e
              Logtail::Config.instance.debug { "Intervaled HTTP flush failed: #{e.inspect}\n\n#{e.backtrace}" }
            end
          end
        end

        # Determines if the loop in {#intervaled_flush} is ready to be flushed again. It
        # uses the `@last_async_flush` variable to ensure that a flush does not happen
        # too rapidly ({#write} also triggers a flush).
        def intervaled_flush_ready?
          @last_async_flush.nil? || (Time.now.to_f - @last_async_flush.to_f).abs >= @flush_interval
        end

        # Builds an `Net::HTTP` object to deliver requests over.
        def build_http
          http = Net::HTTP.new(@ingesting_host, @ingesting_port)
          http.set_debug_output(Config.instance.debug_logger) if Config.instance.debug_logger
          if @ingesting_scheme == 'https'
            http.use_ssl = true
            # Verification on Windows fails despite having a valid certificate.
            http.verify_mode = OpenSSL::SSL::VERIFY_NONE
          end
          http.read_timeout = 30
          http.ssl_timeout = 10
          http.open_timeout = 10
          http
        end

        # Creates a loop that processes the `@request_queue` on an interval. After a failed
        # connection, or a 429 or 5xx response, it waits before reconnecting, twice as long after
        # every consecutive failure up to {MAX_RECONNECT_WAIT}, so an unreachable host is not
        # retried in a busy loop. A Retry-After header can make the wait longer. A delivered
        # request starts the wait over (see {#deliver_requests}).
        def request_outlet
          loop do
            http = build_http
            connection_healthy = false

            begin
              Logtail::Config.instance.debug { "Starting HTTP connection" }

              connection_healthy = http.start do |conn|
                deliver_requests(conn)
              end
            rescue => e
              Logtail::Config.instance.debug { "#request_outlet error: #{e.message}" }
            ensure
              Logtail::Config.instance.debug { "Finishing HTTP connection" }
              http.finish if http.started?
            end

            next if connection_healthy

            Logtail::Config.instance.debug { "Reconnecting in #{@reconnect_wait} seconds" }
            sleep(@reconnect_wait)
            @reconnect_wait = [@reconnect_wait * 2, MAX_RECONNECT_WAIT].min
          end
        end

        # Creates a loop that delivers requests over an open (kept alive) HTTP connection.
        # If the connection dies, the request is thrown back onto the queue and
        # the method returns. It is the responsibility of the caller to implement retries
        # and establish a new connection. A 429 or 5xx response is handled the same way, and
        # a request rejected with any other status is dropped (see {#report_rejected_batch}).
        def deliver_requests(conn)
          num_reqs = 0

          while num_reqs < @requests_per_conn
            if @request_queue.size > 0
              Logtail::Config.instance.debug { "Waiting on next request, threads waiting: #{@request_queue.size}" }
            end

            # Counted as in flight before it leaves the queue, so close never sees neither
            @requests_in_flight += 1
            request_attempt = @request_queue.deq

            if request_attempt.nil?
              @requests_in_flight -= 1
              sleep(1)
            else
              request_attempt.attempted!

              begin
                resp = conn.request(request_attempt.request)
              rescue => e
                Logtail::Config.instance.debug { "#deliver_requests error: #{e.message}" }
                retry_or_drop(request_attempt)
                return false
              ensure
                @requests_in_flight -= 1
              end

              num_reqs += 1

              @last_resp = resp
              delivered = resp.code.start_with?("2")

              Logtail::Config.instance.debug do
                if delivered
                  "Logs successfully sent! View your logs at https://telemetry.betterstack.com"
                else
                  "Log delivery failed! status: #{resp.code}, body: #{resp.body}"
                end
              end

              # A request the server didn't read (408, which Better Stack also sends for a new
              # connection that stayed unused too long), too many requests or a server error: retry
              # the request like after a failed connection, without starting the wait over, and
              # wait as long as Retry-After asks.
              if resp.code == "408" || resp.code == "429" || resp.code.start_with?("5")
                retry_or_drop(request_attempt)
                @reconnect_wait = [@reconnect_wait, retry_after(resp)].max
                return false
              end

              report_rejected_batch(request_attempt, resp) unless delivered
              @reconnect_wait = INITIAL_RECONNECT_WAIT
            end
          end

          true
        end

        # Throws the request back on the queue for a retry if it has been attempted less
        # than 3 times
        def retry_or_drop(request_attempt)
          if request_attempt.attempts < 3
            Logtail::Config.instance.debug { "Request is being retried, #{request_attempt.attempts} previous attempts" }
            @request_queue.enq(request_attempt)
          else
            Logtail::Config.instance.debug { "Request is being dropped, #{request_attempt.attempts} previous attempts" }
          end
        end

        # The seconds to wait before a retry that the Retry-After header asks for, given in
        # seconds or as an HTTP date, at most {MAX_RETRY_AFTER}. 0 without a valid header.
        def retry_after(resp)
          value = resp["Retry-After"].to_s.strip
          seconds = value.match?(/\A\d+\z/) ? value.to_i : (Time.httpdate(value) - Time.now).ceil
          seconds.clamp(0, MAX_RETRY_AFTER)
        rescue ArgumentError
          0
        end

        # Warns about a batch Better Stack rejected, once per HTTP status in this process. It
        # goes to stderr, never to a Logtail logger, whose lines would be rejected the same way.
        def report_rejected_batch(request_attempt, resp)
          first_rejection = REPORTED_REJECTIONS_LOCK.synchronize do
            !REPORTED_REJECTIONS.include?(resp.code) && REPORTED_REJECTIONS.push(resp.code)
          end
          return unless first_rejection

          lines = request_attempt.line_count
          status = "HTTP #{resp.code} #{resp.message}".strip
          hint = " - check your source token" if resp.code == "401" || resp.code == "403"
          warn("Logtail: Better Stack rejected #{lines || "some"} log #{lines == 1 ? "line" : "lines"} " \
            "with #{status}#{hint}. Further rejections with this status won't be reported.")
        end

        # Builds the `Authorization` header value for HTTP delivery to the Logtail API.
        def authorization_payload
          "Bearer #{@source_token}"
        end
    end
  end
end
