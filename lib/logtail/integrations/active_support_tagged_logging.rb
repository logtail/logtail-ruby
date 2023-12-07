# This is an override instead of an integration because without this Logtail would not
# work properly if ActiveSupport::TaggedLogging is used.

require 'logtail/integration'

module Logtail
  module Integrations
    class ActiveSupportTaggedLogging < Integration
      module FormatterMethods
        def self.included(mod)
          mod.module_eval do
            alias_method :_logtail_original_push_tags, :push_tags
            alias_method :_logtail_original_pop_tags, :pop_tags

            def call(severity, timestamp, progname, msg)
              if is_a?(Logtail::Logger::Formatter)
                # Don't convert the message into a string
                super(severity, timestamp, progname, msg)
              else
                super(severity, timestamp, progname, "#{tags_text}#{msg}")
              end
            end
          end
        end
      end

      module LoggerMethods
        def self.included(klass)
          klass.class_eval do
            def add(severity, message = nil, progname = nil, &block)
              if message.nil?
                if block_given?
                  message = block.call
                else
                  message = progname
                  progname = nil #No instance variable for this like Logger
                end
              end
              if @logger.is_a?(Logtail::Logger)
                @logger.add(severity, message, progname)
              else
                @logger.add(severity, "#{tags_text}#{message}", progname)
              end
            end
          end
        end
      end

      def initialize
        require "active_support/tagged_logging"
      rescue LoadError => e
        raise RequirementNotMetError.new(e.message)
      end

      def integrate!
        return integrate_formatter if defined?(tagged_logging_fmt_class)
        return true if tagged_logging_class.include?(LoggerMethods)

        tagged_logging_class.send(:include, LoggerMethods)
      end

      private

      def integrate_formatter
        return true if tagged_logging_fmt_class.include?(FormatterMethods)

        tagged_logging_fmt_class.send(:include, FormatterMethods)
      end

      TAGGED_LOGGING_FORMATTER = '::ActiveSupport::TaggedLogging::Formatter'
      TAGGED_LOGGING = '::ActiveSupport::TaggedLogging'

      def tagged_logging_class
        TAGGED_LOGGING.constantize
      end

      def tagged_logging_fmt_class
        TAGGED_LOGGING_FORMATTER.constantize
      end
    end
  end
end
