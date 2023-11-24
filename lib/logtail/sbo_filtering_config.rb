module Logtail
  module SboFilteringConfig

    FIELD_PATH_SEPARATOR = '->'.freeze

    # Allows to remove specific fields before they are pushed to better stack logs
    #
    # @example
    #   Logtail::LogEntry.ignored_log_field_paths  = %w[
    #       event->http_response_sent->headers_json
    #       context->system
    #       context->runtime
    #   ]
    def ignored_log_field_paths=(value)
      @ignored_log_field_paths = value.map do |field_path|
        Array.wrap(field_path.split(FIELD_PATH_SEPARATOR)).map(&:to_sym)
      end
    end

    def ignored_log_field_paths
      @ignored_log_field_paths
    end
  end
end
