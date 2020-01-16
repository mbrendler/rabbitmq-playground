#! /usr/bin/env ruby
# frozen_string_literal: true

require 'sneakers'
require 'sneakers/Runner'
require 'optparse'

FROM_QUEUE_OPTION_DEFINITIONS = {
  exchange: String,
  routing_key: String,
  timeout_job_after: Integer
}.freeze

EXCHANGE_TYPES = %w[direct fanout topic header]

def parse_options
  queue_name = 'a_test_queue'
  from_options = {
    exchange: 'playground.a-exchange',
    exchange_type: :topic,
    exchange_options: { durable: false },
    routing_key: 'playground.a-routing-key',
    durable: true
  }
  OptionParser.new do |opts|
    opts.banner = "Usage: #{$PROGRAM_NAME} [options]"
    opts.separator('')

    opts.on('--queue QUEUE', 'Use queue') { |value| queue_name = value }
    opts.on('--no-durable', 'Disable durable') do
      from_options[:durable] = false
    end

    opts.on('--exchange-durable', 'Make exchange durable') do
      from_options[:exchange_options][:durable] = true
    end
    opts.on('--exchange-type TYPE', 'Use exchange type') do |v|
      raise "unknown exchange type - '#{v}'" unless EXCHANGE_TYPES.include?(v)

      from_options[:exchange_type] = v.to_sym
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
  from_queue(QUEUE_NAME, **FROM_OPTIONS)

  def work(msg)
    puts msg
    ack! # Tell RabbitMQ that the message is successfully handled.
  end
end

Sneakers::Runner.new([Worker]).run
