Start workers::

   $ sneakers work Processor --require boot.rb

Display Queue Status::

   $ ruby status.rb

Start Publisher::

   $ ruby producer.rb '{"id": "1"}'

Interesting Meta Keys:

   * :message_id
   * :reply_to
   * :correlation
   * :timestamp
   * :arguments


Links:

* http://rubybunny.info/articles/queues.html
* http://rubybunny.info/articles/durability.html
* http://rubybunny.info/articles/exchanges.html
