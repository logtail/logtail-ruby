# frozen_string_literal: true

module Logtail
  module Integrations
    module ActiveSupport
      module LogSubscriberInterface
        extend self

        def find(type)
          log_subscribers.find do |subscriber|
            subscriber.class == type
          end
        end

        def subscribed?(type)
          !find(type).nil?
        end

        def unsubscribe!(component, type)
          return type.detach_from(component) if defined?(type.detach_from)

          subscriber = find(type)

          return unsubscribe_all_listeners(subscriber, component) if subscriber.present?

          raise "We could not find a log subscriber for #{component.inspect} of type #{type.inspect}"
        end

        def unsubscribe_all_listeners(subscriber, component)
          subscriber_methods(subscriber).each do |event|
            active_support_listeners(event, component).each do |listener|
              unsubscribe_listener(listener) if listening?(listener, subscriber)
            end
          end
        end

        def unsubscribe_listener(listener)
          ::ActiveSupport::Notifications.unsubscribe listener
        end

        def listening?(listener, subscriber)
          listener.instance_variable_get('@delegate') == subscriber
        end

        def subscriber_methods(subscriber)
          subscriber.public_methods(false).reject do |method|
            method.to_s == 'call'
          end
        end

        def log_subscribers
          ::ActiveSupport::LogSubscriber.log_subscribers
        end

        def active_support_listeners(event, component)
          ::ActiveSupport::Notifications.notifier.listeners_for("#{event}.#{component}")
        end
      end
    end
  end
end
