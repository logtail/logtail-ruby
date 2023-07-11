# Logtail - Ruby Logging Made Easy
  
  [![Logtail ruby dashboard](https://user-images.githubusercontent.com/19272921/154085622-59997d5a-3f91-4bc9-a815-3b8ead16d28d.jpeg)](https://betterstack.com/logtail)

[![ISC License](https://img.shields.io/badge/license-ISC-ff69b4.svg)](LICENSE.md)
[![Gem Version](https://badge.fury.io/rb/logtail-ruby.svg)](https://badge.fury.io/rb/logtail-ruby)
[![Build Status](https://github.com/logtail/logtail-ruby/workflows/build/badge.svg)](https://github.com/logtail/logtail-ruby/actions?query=workflow%3Abuild)

Collect logs directly from your Ruby projects. To start logging Ruby on Rails projects explore the [Logtail Rails library](https://github.com/logtail/logtail-ruby-rails).

[Logtail](https://betterstack.com/logtail) is a hosted service that centralizes all of your logs into one place. Allowing for analysis, correlation and filtering with SQL. Actionable Grafana dashboards and collaboration come built-in. Logtail works with [any language or platform and any data source](https://docs.logtail.com/). 

### Features
- Simple integration.
- Support for structured logging and events.
- Automatically captures useful context.
- Performant, light weight, with a thoughtful design.

### Supported language versions
- Ruby 2.7.0 or newer

# Installation
Install the Logtail Ruby client library, run the following command:

```bash
bundle add logtail
```

This will install Logtail gem and create `Gemfile` and `Gemfile.lock` that are used to track the code dependencies.

Alternatively, add `gem "logtail"` to your `Gemfile` manually and then run `bundle install`.

---

# Example project

To help you get started with using Logtail in your Ruby projects, we have prepared a simple program that showcases the usage of Logtail logger.

## Download and install the example project

You can download the [example project](https://github.com/logtail/logtail-ruby/tree/main/example-project) from GitHub directly or you can clone it to a select directory. Make sure you are in the projects directory and run the following command:

```bash
bundle install
```

This will install all dependencies listed in the `Gemfile.lock` file.

 ## Run the example project
 
 To run the example application, run the following command:

```bash
bundle exec ruby main.rb <source-token>
```

*Don't forget to replace `<source-token>` with your actual source token which you can find by going to logtail.com -> sources -> edit.*

This will create a total of 5 different logs, each corresponding to a different log level. You can review these logs in Logtail.

## Explore how example project works
 
Learn how to setup Ruby logging by exploring the workings of the [example project](https://github.com/logtail/logtail-ruby/tree/main/example-project) in detail. 
 
---
 
## Get in touch

Have any questions? Please explore the Logtail [documentation](https://docs.logtail.com/) or contact our [support](https://betterstack.com/help).
