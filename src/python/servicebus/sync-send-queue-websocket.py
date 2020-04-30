import os
from azure.servicebus import ServiceBusClient, Message, TransportType

CONNECTION_STR = os.environ['SERVICE_BUS_CONNECTION_STR']
QUEUE_NAME = os.environ["SERVICE_BUS_QUEUE_NAME"]


def send_single_message(sender):
    message = Message("DATA" * 64)
    sender.send(message)


def send_batch_message(sender):
    batch_message = sender.create_batch()
    while True:
        try:
            batch_message.add(Message("DATA" * 256))
        except ValueError:
            # BatchMessage object reaches max_size.
            # New BatchMessage object can be created here to send more data.
            break
    sender.send(batch_message)


servicebus_client = ServiceBusClient.from_connection_string(conn_str=CONNECTION_STR, logging_enable=True, transport_type=TransportType.AmqpOverWebsocket, http_proxy=None)
print(servicebus_client._config.transport_type)
with servicebus_client:
    sender = servicebus_client.get_queue_sender(queue_name=QUEUE_NAME)
    with sender:
        send_single_message(sender)
        send_batch_message(sender)

print("Send message is done.")
