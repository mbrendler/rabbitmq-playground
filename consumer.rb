#! /usr/bin/env ruby
# frozen_string_literal: true

require 'time'
require 'sneakers'
require 'sneakers/Runner'
require 'optparse'
require_relative 'config'
require_relative 'tput'

EXCHANGE_TYPES = %w[direct fanout topic header].freeze

OPTIONS =
  Struct
  .new(:queue, :from_queue_options)
  .new(
    QUEUE_NAME,
    exchange: EXCHANGE,
    exchange_type: EXCHANGE_TYPE,
    exchange_options: EXCHANGE_OPTIONS.dup,
    routing_key: ROUTING_KEY,
    durable: QUEUE_DURABLE
  )

OptionParser.new do |opts|
  opts.banner = "Usage: #{$PROGRAM_NAME} [options]"
  opts.separator('')

  opts.on('--exchange', 'Set exchange name') do |v|
    OPTIONS.from_queue_options[:exchange] = v
  end
  opts.on('--exchange-durable', 'Make exchange durable') do
    OPTIONS.from_queue_options[:exchange_options][:durable] = true
  end
  opts.on('--exchange-type TYPE', 'Use exchange type') do |v|
    raise "unknown exchange type - '#{v}'" unless EXCHANGE_TYPES.include?(v)

    OPTIONS.from_queue_options[:exchange_type] = v.to_sym
  end
  opts.separator('')

  opts.on('--routing-key', 'Set routing-key') do |v|
    OPTIONS.from_queue_options[:routing_key] = v
  end
  opts.separator('')

  opts.on('--queue QUEUE', 'Use queue') { |value| OPTIONS.queue = value }
  opts.on('--no-durable', 'Disable durable') do
    OPTIONS.from_queue_options[:durable] = false
  end
end.parse!

Sneakers.configure(prefetch: 1)
Sneakers.logger.level = Logger::INFO

class Worker
  include Sneakers::Worker
  from_queue(OPTIONS.queue, OPTIONS.from_queue_options)

  def work_with_params(msg, delivery_info, metadata)
    puts("#{Tput.header}New message#{Tput.clean} - #{Time.now.iso8601}")
    print_data(:msg, msg)
    print_data(:delivery_info, delivery_info)
    print_data(:metadata, metadata)
    puts
    ack!
  end

  private

  def print_data(name, data)
    puts("#{Tput.blue}#{name}:#{Tput.clean} #{data.inspect}")
  end
end

Sneakers::Runner.new([Worker]).run
