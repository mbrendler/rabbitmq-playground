# RabbitMQ playground

* Install dependencies

```
bundle install
```

* Start consumer

```
./consumer.rb
```

* Publish message

```
./publisher.rb 'a message' 'another message'
```

* Show queue status

```
./status queue_name
```


## Interesting Meta Keys:

* :message_id
* :reply_to
* :correlation
* :timestamp
* :arguments


Links:

* http://rubybunny.info/articles/queues.html
* http://rubybunny.info/articles/durability.html
* http://rubybunny.info/articles/exchanges.html
