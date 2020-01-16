#! /usr/bin/env ruby
# frozen_string_literal: true

require 'sneakers'
require 'sneakers/Runner'
require 'optparse'

FROM_QUEUE_OPTION_DEFINITIONS = {
  exchange: String,
  # exchange_type: :topic,
  routing_key: String,
  timeout_job_after: Integer
}.freeze

def parse_options
  queue_name = 'a_test_queue'
  from_options = { durable: true }
  OptionParser.new do |opts|
    opts.banner = "Usage: #{$PROGRAM_NAME} [options]"
    opts.separator('')

    opts.on('--queue QUEUE', 'Use queue') { |value| queue_name = value }
    opts.on('--no-durable', 'Disable durable') do
      from_options[:durable] = false
    end

    FROM_QUEUE_OPTION_DEFINITIONS.each do |name, type|
      opts.on(
        "--#{name} #{name.to_s.upcase}", type, "Set #{name} (#{type})"
      ) do |value|
        from_options[name] = value
      end
    end
  end.parse!
  [queue_name, from_options]
end

QUEUE_NAME, FROM_OPTIONS = parse_options

Sneakers.configure(prefetch: 1)
Sneakers.logger.level = Logger::INFO

class Worker
  include Sneakers::Worker
  from_queue(
    QUEUE_NAME,
    exchange_options: { durable: true },
    **FROM_OPTIONS
  )

  def work(msg)
    puts msg
    ack! # Tell RabbitMQ that the message is successfully handled.
  end
end

Sneakers::Runner.new([Worker]).run
