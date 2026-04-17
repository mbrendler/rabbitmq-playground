// c++ -Wall -Wextra -Wpedantic -I/opt/homebrew/include -L/opt/homebrew/lib
// -lrabbitmq -o publisher-c++ publisher-c++.cpp

#include <rabbitmq-c/amqp.h>
#include <rabbitmq-c/ssl_socket.h>
#include <rabbitmq-c/tcp_socket.h>
#include <mutex>
#include <stdio.h>
#include <stdlib.h>
#include <string>

class RmqPublisher {
public:
  explicit RmqPublisher(const char *url) : m_url(strdup(url)) {
    amqp_default_connection_info(&m_conn_info);
    if (!m_url) {
      m_error = "allocating URL string";
      return;
    }
    int rc = amqp_parse_url(m_url, &m_conn_info);
    if (rc != AMQP_STATUS_OK) {
      m_error = "parsing URL";
      return;
    }

    connect();
  }
  RmqPublisher(const RmqPublisher &) = delete;
  RmqPublisher &operator=(const RmqPublisher &) = delete;
  RmqPublisher(RmqPublisher &&) = delete;
  RmqPublisher &operator=(RmqPublisher &&) = delete;
  ~RmqPublisher() {
    free(m_url);
    // if (m_conn_info.ssl) {
    //   amqp_uninitialize_ssl_library();
    // }
    if (!m_conn) {
      return;
    }
    amqp_channel_close(m_conn, 1, AMQP_REPLY_SUCCESS);
    amqp_connection_close(m_conn, AMQP_REPLY_SUCCESS);
    amqp_destroy_connection(m_conn);
  }

  std::string create_exchange(const char *exchange) {
    std::lock_guard<std::mutex> lock(m_mutex);
    if (!m_conn) {
      return m_error;
    }
    amqp_maybe_release_buffers(m_conn);

    amqp_exchange_declare(m_conn, 1, amqp_cstring_bytes(exchange),
                          amqp_cstring_bytes("topic"),
                          /*passive=*/0,
                          /*durable=*/1,
                          /*auto_delete=*/0,
                          /*internal=*/0, amqp_empty_table);
    amqp_rpc_reply_t reply = amqp_get_rpc_reply(m_conn);
    const std::string err = rpc_error("Declaring exchange", reply);
    if (!err.empty()) {
      teardown();
    }
    return err;
  }

  std::string publish(const char *message, const char *routing_key,
                      const char *exchange) {
    std::lock_guard<std::mutex> lock(m_mutex);
    if (!m_conn) {
      return m_error;
    }
    amqp_maybe_release_buffers(m_conn);

    amqp_bytes_t message_bytes = amqp_cstring_bytes(message);
    amqp_bytes_t routing_key_bytes = amqp_cstring_bytes(routing_key);
    amqp_bytes_t exchange_bytes = amqp_cstring_bytes(exchange);
#ifdef CHECK_PUBLISHER_CONFIRM
    const int mandatory = 1;
#else
    const int mandatory = 0;
#endif
    const int rc =
        amqp_basic_publish(m_conn, 1, exchange_bytes, routing_key_bytes,
                           mandatory, 0, NULL, message_bytes);
    if (rc != AMQP_STATUS_OK) {
      teardown();
      return std::string("Publishing message: ") + amqp_error_string2(rc);
    }
#ifdef CHECK_PUBLISHER_CONFIRM
    bool returned = false;
    amqp_frame_t frame;
    for (;;) {
      if (amqp_simple_wait_frame(m_conn, &frame) != AMQP_STATUS_OK) {
        teardown();
        return "Waiting for publisher confirm: frame error";
      }
      if (frame.frame_type != AMQP_FRAME_METHOD) continue;
      if (frame.payload.method.id == AMQP_BASIC_ACK_METHOD) break;
      if (frame.payload.method.id == AMQP_BASIC_NACK_METHOD) {
        return "Message was nack'd by the broker";
      }
      if (frame.payload.method.id == AMQP_BASIC_RETURN_METHOD) {
        returned = true;
        amqp_simple_wait_frame(m_conn, &frame); // content header
        if (frame.frame_type == AMQP_FRAME_HEADER) {
          uint64_t remaining = frame.payload.properties.body_size;
          while (remaining > 0) {
            amqp_simple_wait_frame(m_conn, &frame); // body chunk
            if (frame.frame_type == AMQP_FRAME_BODY)
              remaining -= frame.payload.body_fragment.len;
          }
        }
        continue; // ack still follows
      }
      if (frame.payload.method.id == AMQP_CHANNEL_CLOSE_METHOD) {
        teardown();
        return "Channel was closed by the broker";
      }
    }
    if (returned) {
      return "Message was returned: unroutable";
    }
#endif

    return "";
  }

  const std::string &error() const { return m_error; }

private:
  void connect() {
    m_conn = amqp_new_connection();
    if (!m_conn) {
      m_error = "creating connection";
      return;
    }
    amqp_socket_t *socket = nullptr;
    if (m_conn_info.ssl) {
      socket = amqp_ssl_socket_new(m_conn);
    } else {
      socket = amqp_tcp_socket_new(m_conn);
    }

    if (!socket) {
      m_error = "creating TCP socket";
      amqp_destroy_connection(m_conn);
      m_conn = nullptr;
      return;
    }
    if (m_conn_info.ssl) {
      amqp_ssl_socket_set_verify_peer(socket, 0);
      amqp_ssl_socket_set_verify_hostname(socket, 0);
    }

    const int rc = amqp_socket_open(socket, m_conn_info.host, m_conn_info.port);
    if (rc != AMQP_STATUS_OK) {
      m_error = "opening TCP socket";
      amqp_destroy_connection(m_conn);
      m_conn = nullptr;
      return;
    }

    // Heartbeat (5th arg) only flows while a rabbitmq-c API call is running;
    // on an idle connection a caller must periodically invoke something like
    // amqp_simple_wait_frame_noblock to keep it alive / detect drops.
    amqp_rpc_reply_t ret = amqp_login(m_conn, m_conn_info.vhost, 0, 131072, 60,
                                      AMQP_SASL_METHOD_PLAIN, m_conn_info.user,
                                      m_conn_info.password);
    m_error = rpc_error("Logging in", ret);
    if (!m_error.empty()) {
      amqp_connection_close(m_conn, AMQP_REPLY_SUCCESS);
      amqp_destroy_connection(m_conn);
      m_conn = nullptr;
      return;
    }

    amqp_channel_open(m_conn, 1);
    ret = amqp_get_rpc_reply(m_conn);
    m_error = rpc_error("Open channel", ret);
    if (!m_error.empty()) {
      amqp_connection_close(m_conn, AMQP_REPLY_SUCCESS);
      amqp_destroy_connection(m_conn);
      m_conn = nullptr;
      return;
    }

#ifdef CHECK_PUBLISHER_CONFIRM
    amqp_confirm_select(m_conn, 1);
    amqp_rpc_reply_t reply = amqp_get_rpc_reply(m_conn);
    m_error = rpc_error("Enabling publisher confirms", reply);
    if (!m_error.empty()) {
      amqp_connection_close(m_conn, AMQP_REPLY_SUCCESS);
      amqp_destroy_connection(m_conn);
      m_conn = nullptr;
      return;
    }
#endif
  }

  void reconnect() {
    if (m_conn) {
      amqp_destroy_connection(m_conn);
      m_conn = nullptr;
    }
    m_error.clear();
    connect();
  }

  void teardown() {
    amqp_destroy_connection(m_conn);
    m_conn = nullptr;
  }

  static std::string rpc_error(const char *context, amqp_rpc_reply_t reply) {
    switch (reply.reply_type) {
    case AMQP_RESPONSE_NORMAL:
      return "";
    case AMQP_RESPONSE_NONE:
      return std::string(context) + ": no reply from broker (connection lost?)";
    case AMQP_RESPONSE_LIBRARY_EXCEPTION:
      return std::string(context) + ": " + amqp_error_string2(reply.library_error);
    case AMQP_RESPONSE_SERVER_EXCEPTION:
      if (reply.reply.id == AMQP_CHANNEL_CLOSE_METHOD) {
        const auto *m = static_cast<amqp_channel_close_t *>(reply.reply.decoded);
        return std::string(context) + ": server channel error " +
               std::to_string(m->reply_code) + " " +
               std::string(static_cast<char *>(m->reply_text.bytes), m->reply_text.len);
      }
      if (reply.reply.id == AMQP_CONNECTION_CLOSE_METHOD) {
        const auto *m = static_cast<amqp_connection_close_t *>(reply.reply.decoded);
        return std::string(context) + ": server connection error " +
               std::to_string(m->reply_code) + " " +
               std::string(static_cast<char *>(m->reply_text.bytes), m->reply_text.len);
      }
      return std::string(context) + ": server exception (method 0x" +
             std::to_string(reply.reply.id) + ")";
    }
    return std::string(context) + ": unexpected reply_type";
  }

  // Using a mutex is enough for now.  With more traffic on the publisher, we should implement a better approach (connection pool or thread with queue).
  std::mutex m_mutex;
  std::string m_error;
  char *m_url = nullptr;
  amqp_connection_info m_conn_info;
  amqp_connection_state_t m_conn = nullptr;
};

int main(int argc, char *argv[]) {
  const char *url = getenv("RABBITMQ_URL");
  if (!url) {
    url = "amqp://127.0.0.1:5672";
  }

  RmqPublisher publisher(url);
  if (publisher.error().size() > 0) {
    fprintf(stderr, "%s\n", publisher.error().c_str());
    return 1;
  }

  const char *message = "Hello, world!";
  if (argc > 1) {
    message = argv[1];
  }

  std::string error = publisher.create_exchange("playground.a-exchange");
  if (error.size() > 0) {
    fprintf(stderr, "%s\n", error.c_str());
    return 1;
  }

  error = publisher.publish(message, "playground.a-routing-key",
                            "playground.a-exchange");
  if (error.size() > 0) {
    fprintf(stderr, "%s\n", error.c_str());
    return 1;
  }

  getchar();

  return 0;
}
