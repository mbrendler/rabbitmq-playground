// cc -Wall -Wextra -Wpedantic -I/opt/homebrew/include -L/opt/homebrew/lib
// -lrabbitmq -o publisher-c publisher-c.c

#include <rabbitmq-c/amqp.h>
#include <rabbitmq-c/tcp_socket.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#define HOSTNAME "127.0.0.1"
/* #define PORT 5672 */
#define PORT 4444

void die_on_amqp_error(amqp_rpc_reply_t x, char const *context) {
  switch (x.reply_type) {
  case AMQP_RESPONSE_NORMAL:
    return;

  case AMQP_RESPONSE_NONE:
    fprintf(stderr, "%s: missing RPC reply type!\n", context);
    break;

  case AMQP_RESPONSE_LIBRARY_EXCEPTION:
    fprintf(stderr, "%s: %s\n", context, amqp_error_string2(x.library_error));
    break;

  case AMQP_RESPONSE_SERVER_EXCEPTION:
    switch (x.reply.id) {
    case AMQP_CONNECTION_CLOSE_METHOD: {
      amqp_connection_close_t *m = (amqp_connection_close_t *)x.reply.decoded;
      fprintf(stderr, "%s: server connection error %u, message: %.*s\n",
              context, m->reply_code, (int)m->reply_text.len,
              (char *)m->reply_text.bytes);
      break;
    }
    case AMQP_CHANNEL_CLOSE_METHOD: {
      amqp_channel_close_t *m = (amqp_channel_close_t *)x.reply.decoded;
      fprintf(stderr, "%s: server channel error %u, message: %.*s\n", context,
              m->reply_code, (int)m->reply_text.len,
              (char *)m->reply_text.bytes);
      break;
    }
    default:
      fprintf(stderr, "%s: unknown server error, method id 0x%08X\n", context,
              x.reply.id);
      break;
    }
    break;
  }

  exit(1);
}

int main(int argc, char *argv[]) {
  char *message = "Hello, world!";
  if (argc > 1) {
    message = argv[1];
  }

  amqp_connection_state_t conn = amqp_new_connection();
  amqp_socket_t *socket = amqp_tcp_socket_new(conn);
  if (!socket) {
    fprintf(stderr, "creating TCP socket\n");
    exit(1);
  }

  int rc = amqp_socket_open(socket, HOSTNAME, PORT);
  if (rc) {
    fprintf(stderr, "opening TCP socket\n");
    exit(1);
  }

  die_on_amqp_error(amqp_login(conn, "/", 0, 131072, 0, AMQP_SASL_METHOD_PLAIN,
                               "guest", "guest"),
                    "Logging in");

  amqp_channel_open(conn, 1);
  die_on_amqp_error(amqp_get_rpc_reply(conn), "Opening channel");

  {
    amqp_bytes_t message_bytes = (amqp_bytes_t){
        .len = strlen(message),
        .bytes = message,
    };

    rc =
        amqp_basic_publish(conn, 1, amqp_literal_bytes("playground.a-exchange"),
                           amqp_literal_bytes("playground.a-routing-key"), 0, 0,
                           NULL, message_bytes);
    if (rc < 0) {
      fprintf(stderr, "Publishing message: %s\n", amqp_error_string2(rc));
    }

    printf("Press Enter to publish another message...\n");
    getchar();

    rc =
        amqp_basic_publish(conn, 1, amqp_literal_bytes("playground.a-exchange"),
                           amqp_literal_bytes("playground.a-routing-key"), 0, 0,
                           NULL, message_bytes);
    if (rc < 0) {
      fprintf(stderr, "Publishing message: %s\n", amqp_error_string2(rc));
    }

    /* send_batch(conn, amqp_literal_bytes("test queue"), rate_limit,
     * message_count); */
  }

  die_on_amqp_error(amqp_channel_close(conn, 1, AMQP_REPLY_SUCCESS),
                    "Closing channel");
  die_on_amqp_error(amqp_connection_close(conn, AMQP_REPLY_SUCCESS),
                    "Closing connection");
  rc = amqp_destroy_connection(conn);
  if (rc < 0) {
    fprintf(stderr, "Ending connection: %s\n", amqp_error_string2(rc));
  }

  return 0;
}
