require 'logtail/integration'

module Logtail
  module Frameworks
    # Installs Logtail into your Rails app automatically.
    class Railtie < ::Rails::Railtie
      railtie_name 'logtail-rails'

      config.logtail = Config.instance

      config.before_initialize do
        Logtail::Config.instance.logger = Proc.new { ::Rails.logger }
      end

      # Must be loaded after initializers so that we respect any Logtail configuration set
      initializer(:logtail, before: :build_middleware_stack, after: :load_config_initializers) do
        Integration.integrate!

        # Install the Rack middlewares so that we capture structured data instead of
        # raw text logs.
        Integration.middlewares.collect do |middleware_class|
          config.app_middleware.use middleware_class
        end
      end
    end
  end
end
