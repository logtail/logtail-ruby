require "json"

require "logtail/util/non_nil_hash_builder"

module Logtail
  # @private
  module Util
    # Encodes data as JSON. With ActiveSupport loaded, the data is converted with `as_json` first,
    # so values come out as ActiveSupport's `to_json` encoded them (times in ISO 8601, NaN as
    # null, ...), but without its encoder: with json 3, ActiveSupport 8.0 and older raise from it.
    def self.generate_json(data)
      ::JSON.generate(data.respond_to?(:as_json) ? data.as_json : data)
    end
  end
end
