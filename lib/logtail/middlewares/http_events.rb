# frozen_string_literal: true

# Extracted from Logtail Ruby Rack gem
# https://github.com/logtail/logtail-ruby-rack

require "set"

require "logtail/config"
require "logtail/middleware"
require "logtail/contexts/http"
require "logtail/current_context"
require "logtail/formatters/http_request"
require "logtail/formatters/http_response"
require "logtail/util/encoding"

module Logtail
  module Middlewares
    class HttpEvents < Middleware
      class << self
        # Allows you to capture the HTTP request body, default is off (false).
        #
        # Capturing HTTP bodies can be extremely helpful when debugging issues,
        # but please proceed with caution:
        #
        # 1. Capturing HTTP bodies can use quite a bit of data (this can be mitigated, see below)
        #
        # If you opt to capture bodies, you can also truncate the size to reduce the data
        # captured. See {Events::HTTPRequest}.
        #
        # @example
        #   Logtail::Integrations::HttpEvents.capture_request_body = true
        def capture_request_body=(value)
          @capture_request_body = value
        end

        # Accessor method for {#capture_request_body=}
        def capture_request_body?
          @capture_request_body == true
        end

        # Just like {#capture_request_body=} but for the {Events::HTTPResponse} event.
        # Please see {#capture_request_body=} for more details. The documentation there also
        # applies here.
        def capture_response_body=(value)
          @capture_response_body = value
        end

        # Accessor method for {#capture_response_body=}
        def capture_response_body?
          @capture_response_body == true
        end

        # This setting allows you to silence requests based on any conditions you desire.
        # We require a block because it gives you complete control over how you want to
        # silence requests. The first parameter being the traditional Rack env hash, the
        # second being a [Rack Request](http://www.rubydoc.info/gems/rack/Rack/Request) object.
        #
        # @example
        #   Integrations::Rack::HTTPEvents.silence_request = lambda do |rack_env, rack_request|
        #     rack_request.path == "/_health"
        #   end
        def silence_request=(proc)
          if proc && !proc.is_a?(Proc)
            raise ArgumentError.new("The value passed to #silence_request must be a Proc")
          end

          @silence_request = proc
        end

        # Accessor method for {#silence_request=}
        def silence_request
          @silence_request
        end

        def normalize_header_name(name)
          name.to_s.downcase.gsub("-", "_")
        end
      end

      CONTENT_LENGTH_KEY = 'Content-Length'.freeze

      ERROR_STATUS_MAPPING = {
        'ActiveRecord::RecordNotFound' => 404,
        'ActiveRecord::RecordInvalid' => 422,
        'ActionController::InvalidAuthenticityToken' => 422,
        'ActionController::ParameterMissing' => 400,
        'ActionDispatch::Http::Parameters::ParseError' => 400,
      }.freeze

      def call(env)
        request = Util::Request.new(env)

        if silenced?(env, request)
          if Config.instance.logger.respond_to?(:silence)
            Config.instance.logger.silence do
              @app.call(env)
            end
          else
            @app.call(env)
          end
        else
          begin
            log_http_events(env, request)
          rescue Exception => exception
            Config.instance.logger.fatal do
              status = ERROR_STATUS_MAPPING[exception.class.to_s] || 500

              response = formatted_http_response(request, status, nil, nil)
              {
                message: exception.message,
                event: {
                  http_response_sent: {
                    request_id: response.request_id,
                    status: response.status
                  }
                }
              }
            end

            raise exception
          end
        end
      end

      private

      def log_http_events(env, request)
        Config.instance.logger.info do
          event_body = capture_request_body? ? request.body_content : nil
          http_request = formatted_http_request request, event_body

          {
            message: http_request.message,
            event: {
              http_request_received: {
                body: http_request.body,
                content_length: http_request.content_length,
                headers_json: http_request.headers_json,
                host: http_request.host,
                method: http_request.method,
                path: http_request.path,
                port: http_request.port,
                query_string: http_request.query_string,
                request_id: http_request.request_id,
                scheme: http_request.scheme,
                service_name: http_request.service_name,
              }
            }
          }
        end

        request_start = Time.now
        status, headers, body = @app.call(env)
        request_end = Time.now

        Config.instance.logger.info do
          event_body = capture_response_body? ? body : nil
          duration_ms = (request_end - request_start) * 1000.0

          http_response = formatted_http_response(
            request,
            status,
            event_body,
            duration_ms
          )

          {
            message: http_response.message,
            event: {
              http_response_sent: {
                body: http_response.body,
                request_id: http_response.request_id,
                status: http_response.status,
                duration_ms: http_response.duration_ms,
              }
            }
          }
        end

        [status, headers, body]
      end

      def capture_request_body?
        self.class.capture_request_body?
      end

      def capture_response_body?
        self.class.capture_response_body?
      end

      def collapse_into_single_event?
        self.class.collapse_into_single_event?
      end

      def silenced?(env, request)
        if !self.class.silence_request.nil?
          self.class.silence_request.call(env, request)
        else
          false
        end
      end

      def formatted_http_request(request, event_body)
        Formatters::HttpRequest.new(
          body: event_body,
          content_length: safe_to_i(request.content_length),
          host: Util::Encoding.force_utf8_encoding(request.host),
          method: request.request_method,
          path: request.path,
          query_string: Util::Encoding.force_utf8_encoding(request.query_string),
          request_id: request.request_id
        )
      end

      def formatted_http_response(request, status, event_body, duration_ms)
        Formatters::HttpResponse.new(
          body: event_body,
          request_id: request.request_id,
          status: status,
          duration_ms: duration_ms
        )
      end

      def safe_to_i(val)
        val.nil? ? nil : val.to_i
      end
    end
  end
end
