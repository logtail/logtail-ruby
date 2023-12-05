module Logtail
  module Integrations
    class SidekiqLogger < Integration
      module InstanceMethods
        def self.included(klass)
          klass.class_eval do
            def call(_item, _queue)
              start = Process.clock_gettime(Process::CLOCK_MONOTONIC)

              Logtail::CurrentContext.with({ sidekiq: Sidekiq::Context.current.to_h }) do
                @logger.info("start")

                yield
              end

              Sidekiq::Context.add(:elapsed, elapsed(start))
              Logtail::CurrentContext.with({ sidekiq: Sidekiq::Context.current.to_h }) do
                @logger.info('done')
              end
            rescue Exception
              Sidekiq::Context.add(:elapsed, elapsed(start))
              Logtail::CurrentContext.with({ sidekiq: Sidekiq::Context.current.to_h }) do
                @logger.info('fail')
              end

              raise
            end

            private

            def elapsed(start)
              (Process.clock_gettime(::Process::CLOCK_MONOTONIC) - start).round(3)
            end
          end
        end
      end

      def initialize
        require 'sidekiq/job_logger'
      rescue LoadError => e
        raise RequirementNotMetError.new(e.message)
      end

      def integrate!
        return true if ::Sidekiq::JobLogger.include?(InstanceMethods)

        ::Sidekiq::JobLogger.send(:include, InstanceMethods)
      end
    end
  end
end
