# Copyright © 2021 Michael Lopez
# 
# Permission is hereby granted, free of charge, to any person obtaining a copy of
# this software and associated documentation files (the “Software”), to deal in
# the Software without restriction, including without limitation the rights to
# use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies
# of the Software, and to permit persons to whom the Software is furnished to do
# so, subject to the following conditions:
# 
# The above copyright notice and this permission notice shall be included in all
# copies or substantial portions of the Software.

# THE SOFTWARE IS PROVIDED “AS IS”, WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.

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
