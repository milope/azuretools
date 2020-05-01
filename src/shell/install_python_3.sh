#!/bin/sh

sudo apt-get update -y
sudo apt install python3 -q --yes
sudo apt install python3-pip -q --yes
sudo update-alternatives --install /usr/bin/python3 python3 /usr/bin/python3.6 1
sudo update-alternatives --install /usr/bin/python3 python3 /usr/bin/python3.7 2
#sudo update-alternatives --config python3
sudo apt autoremove
sudo pip3 install azure-eventhub --pre -q
