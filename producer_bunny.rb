require 'bunny'

def main
  connection = Bunny.new
  connection.start
  channel = connection.create_channel
  queue = channel.queue(:calc, durable: true)
  puts "publish: #{ARGV[0]}"
  # :default_exchange is a direct exchange with no name (''):
  channel.default_exchange.publish(ARGV[0], routing_key: queue.name)
  puts 'done'
end

main if __FILE__ == $PROGRAM_NAME
