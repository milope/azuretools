#!/bin/sh

sudo apt install python3 -f
sudo apt install python3-pip -f
sudo update-alternatives --install /usr/bin/python3 python3 /usr/bin/python3.6 1
sudo update-alternatives --install /usr/bin/python3 python3 /usr/bin/python3.7 2
#sudo update-alternatives --config python3
sudo pip3 install azure-eventhub --pre
