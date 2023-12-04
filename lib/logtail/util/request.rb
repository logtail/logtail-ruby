# frozen_string_literal: true

# Extracted from Logtail Ruby Rack gem
# https://github.com/logtail/logtail-ruby-rack

module Logtail
  module Util
    class Request < ::Rack::Request
      HTTP_HEADER_ORIGINAL_DELIMITER = '_'
      HTTP_HEADER_NEW_DELIMITER = '_'
      HTTP_PREFIX = 'HTTP_'

      REMOTE_IP_KEY_NAME = 'action_dispatch.remote_ip'
      REQUEST_ID_KEY_NAME1 = 'action_dispatch.request_id'
      REQUEST_ID_KEY_NAME2 = 'HTTP_X_REQUEST_ID'

      def body_content
        content = body.read
        body.rewind
        content
      end

      # Returns a list of request headers. The rack env contains a lot of data, this function
      # identifies those that were the actual request headers.
      #
      # This was extracted from: https://github.com/ruby-grape/grape/blob/91c6c78ae3d3f3ffabaf57ffc4dc35ab7cfc7b5f/lib/grape/request.rb#L30
      def headers
        @headers ||= extract_headers
      end

      def extract_headers
        headers = {}

        @env.each_pair do |k, v|
          next unless k.is_a?(String) && k.to_s.start_with?(HTTP_PREFIX)

          k = k[5..-1].
            split(HTTP_HEADER_ORIGINAL_DELIMITER).
            each(&:capitalize!).
            join(HTTP_HEADER_NEW_DELIMITER)

          headers[k] = v
        end

        headers
      end

      def ip
        @ip ||= extract_ip_addr
      end

      def extract_ip_addr
        return super if @env[REMOTE_IP_KEY_NAME].blank?
        @env[REMOTE_IP_KEY_NAME].to_s || super
      end

      def referer
        # Rails 3.X returns "/" for some reason
        @referer ||= super == "/" ? nil : super
      end

      def request_id
        @request_id ||= @env[REQUEST_ID_KEY_NAME1] ||
          @env[REQUEST_ID_KEY_NAME2]
      end
    end
  end
end
