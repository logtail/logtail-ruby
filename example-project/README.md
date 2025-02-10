# Example project

To help you get started with using Logtail in your Ruby projects, we have prepared a simple program that showcases the usage of Logtail logger.

## Download and install the example project

You can download the example project from GitHub directly or you can clone it to a select directory. Make sure you are in the projects directory and run the following command:

```bash
bundle install
```

This will install all dependencies listed in the `Gemfile.lock` file.

Alternatively, add `gem "logtail"` to your `Gemfile` manually and then run `bundle install`.

 ## Run the example project

_Don't forget to replace `<source_token>` and `<ingesting_host>` with your actual source token and ingesting host which you can find by going to **[Sources](https://telemetry.betterstack.com/team/0/sources) -> Configure** in Better Stack._ 

 To run the example application, run the following command adding your source token:

```bash
bundle exec ruby main.rb <source_token> <ingesting_host>
```

This will create a total of 5 different logs, each corresponding to a different log level. You can review these logs in Logtail.

# Logging

The `logger` instance we created in the installation section is used to send log messages to Logtail. It provides 5 logging methods for the 5 default log levels. The log levels and their method are:

- **DEBUG** - Send debug messages using the `debug()` method
- **INFO** - Send informative messages about the application progress using the `info()` method
- **WARN** - Report non-critical issues using the `warn()` method
- **ERROR** - Send messages about serious problems using the `error()` method
- **FATAL** - Send messages about fatal events that caused the app to crash using the `fatal()` method

## Logging example

In this example, we will send two logs - **DEBUG** and **INFO**

```ruby
# Send debug logs messages using the debug() method
logger.debug("Logtail is ready!")

# Send informative messages about interesting events using the info() method
logger.info("I am using Logtail!")
```

This will create the following output:

```json
{
    "dt": "2021-03-29T11:24:54.788Z",
    "level": "debug",
    "message": "Logtail is ready!",
    "context": {
        "runtime": {
            "thread_id": 123,
            "file": "main.rb",
            "line": 6,
            "frame": null,
            "frame_label": "<main>"
        },
        "system": {
            "hostname": "hostname"
            "pid": 1234
        }
    }
}

{
    "dt": "2021-03-29T11:24:54.788Z",
    "level": "info",
    "message": "I am using Logtail!",
    "context": {
        "runtime": {
            "thread_id": 123,
            "file": "main.rb",
            "line": 6,
            "frame": null,
            "frame_label": "<main>"
        },
        "system": {
            "hostname": "hostname"
            "pid": 1234
        }
    }
}
```

## Log structured data

You can also log additional structured data. This can help you provide additional information when debugging and troubleshooting your application. You can provide this data as the second argument to any logging method.

```ruby
# Send messages about worrying events using the warn() method
# You can also log additional structured data
logger.warn(
    "log structured data",
    item: {
        url: "https://fictional-store.com/item-123",
        price: 100.00
    }
)
```

This will create the following output:

```json
{
    "dt": "2021-03-29T11:24:54.788Z",
    "level": "warn",
    "message": "log structured data",
    "item": {
        "url": "https://fictional-store.com/item-123",
        "price": 100.00
    },
    "context": {
        "runtime": {
            "thread_id": 123,
            "file": "main.rb",
            "line": 7,            
            "frame": null,
            "frame_label": "<main>"
        },
        "system": {
            "hostname": "hostname"
            "pid": 1234
        }
    }
}
```

## Context

We add information about the current runtime environment and the current process into a `context` field of the logged item by default.

If you want to add custom information to all logged items (e.g., the ID of the current user), you can do so by adding a custom context:

```ruby
# Provide context to the logs
Logtail.with_context(user: { id: 123 }) do
    logger.info('new subscription')
end
```

This will generate the following JSON output:

```json
{
    "dt": "2021-03-29T11:24:54.788Z",
    "level": "warn",
    "message": "new subscription",
    "context": {
        "runtime": {
            "thread_id": 123456,
            "file": "main.rb",
            "line": 2,            
            "frame": null,
            "frame_label": "<main>"
        },
        "system": {
            "hostname": "hostname"
            "pid": 1234
        },
        "user": {
            "id": 123
        }
    }
}
```

We will automatically add the information about the current user to each log if you're using Ruby on Rails and the Devise gem.

If you're not using Devise or you want to log some additional information for every request your Rails app handles, you can easily implement this using Rails' `around_action` in your application controller. A simple implementation could look like this:

```ruby
class ApplicationController < ActionController::Base
  around_action :with_logtail_context

  private

    def with_logtail_context
      if user_signed_in?
        Logtail.with_context(user_context) { yield }
      else
        yield
      end
    end
    
    def user_context
      Logtail::Contexts::User.new(
        id: current_user.id,
        name: current_user.name,
        email: current_user.email
      )
    end
end
```
