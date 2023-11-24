module Logtail
  module Util
    class Cleaner
      def self.filter_logged_fields(ignored_log_field_paths, log_hash)
        Array.wrap(ignored_log_field_paths).each do |field_path|
          next if path_missing?(log_hash, field_path)
          deep_key_remover log_hash, field_path.dup
        end

        log_hash
      end

      def self.path_missing?(log_hash, field_path)
        log_hash.dig(*field_path).nil?
      rescue
        true
      end

      def self.deep_key_remover(log_hash, field_path)
        extracted_field = field_path.shift
        return deep_key_remover(log_hash[extracted_field], field_path) unless field_path.empty?
        log_hash.delete extracted_field
      end
    end
  end
end
