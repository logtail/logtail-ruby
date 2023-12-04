# Extracted from Logtail Ruby Rack gem
# https://github.com/logtail/logtail-ruby-rack

require "logtail/util/encoding"

module Logtail
  module Formatters
    class HttpResponse
      attr_reader :body, :content_length, :headers, :headers_json, :http_context, :request_id, :service_name,
        :status, :duration_ms

      def initialize(attributes)
        @body = attributes[:body]
        @content_length  = attributes[:content_length]
        @headers = attributes[:headers]
        @http_context = attributes[:http_context]
        @request_id = attributes[:request_id]
        @service_name = attributes[:service_name]
        @status = attributes[:status]
        @duration_ms = attributes[:duration_ms]

        if @headers
          @headers_json = Util::Encoding.force_utf8_encoding(@headers).to_json
        end
      end

      # Returns the human readable log message for this event.
      def message
        if http_context
          message = "#{http_context[:method]} #{http_context[:path]} completed with " \
            "#{status} #{status_description} "

          if content_length
            message << ", #{content_length} bytes, "
          end

          message << "in #{duration_ms}ms"
        else
          message = "Completed #{status} #{status_description} "

          if content_length
            message << ", #{content_length} bytes, "
          end

          message << "in #{duration_ms}ms"
        end
      end

      def status_description
        ::Rack::Utils::HTTP_STATUS_CODES[status]
      end
    end
  end
end
