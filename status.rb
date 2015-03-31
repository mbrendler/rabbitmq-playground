require 'bunny'
require 'pp'

def main
  connection = Bunny.new
  connection.start
  channel = connection.channel
  queue = channel.queue(:calc, durable: true, passive: true)
  pp queue.status # Only {message_count: ?, consumer_count: ?}
end

main if __FILE__ == $PROGRAM_NAME
