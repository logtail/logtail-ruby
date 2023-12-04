# frozen_string_literal: true

# Extracted from Logtail Ruby Rack gem
# https://github.com/logtail/logtail-ruby-rack

module Logtail
  module Util
    class Encoding
      def self.force_utf8_encoding(data)
        if data.respond_to?(:force_encoding)
          encoded_data = data.dup.force_encoding('UTF-8')
          encoded_data = data.dup.force_encoding("ISO-8859-1").encode("UTF-8") unless encoded_data.valid_encoding?
          encoded_data = data.dup.encode('UTF-8', invalid: :replace, undef: :replace) unless encoded_data.valid_encoding?
          encoded_data
        elsif data.respond_to?(:transform_values)
          data.transform_values { |val| self.class.force_utf8_encoding(val) }
        else
          data
        end
      end
    end
  end
end
