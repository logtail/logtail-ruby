module Logtail
  # Base class for `Logtail::Integrations::*`. Provides a common interface for all integrators.
  # An integrator is a single specific integration into a part of a library. See
  # {Integration} for higher library level integration settings.
  class Integration
    # Raised when an integrators requirements are not met. For example, this will be raised
    # in the ActiveRecord integration if ActiveRecord is not available as a dependency in
    # the current application.
    class RequirementNotMetError < StandardError; end

    class << self
      attr_writer :enabled

      def enabled=(value)
        @enabled = value
      end

      def enabled?
        @enabled != false
      end

      def silence=(value)
        @silence = value
      end

      def silence?
        @silence == true
      end

      def integrations
        @integrations ||= [
          Integrations::RackLogger,
          Integrations::SidekiqLogger,
        ].select(&:enabled?)
      end

      def integrate!(*args)
        if !enabled?
          Config.instance.debug_logger.debug("#{name} integration disabled, skipping") if Config.instance.debug_logger
          return false
        end

        new(*args).integrate!
        Config.instance.debug_logger.debug("Integrated #{name}") if Config.instance.debug_logger
        true
        # RequirementUnsatisfiedError is the only silent failure we support
      rescue RequirementNotMetError => e
        Config.instance.debug_logger.debug("Failed integrating #{name}: #{e.message}") if Config.instance.debug_logger
        false
      end
    end

    # Abstract method that each integration must implement.
    def integrate!
      raise NotImplementedError.new
    end
  end
end
