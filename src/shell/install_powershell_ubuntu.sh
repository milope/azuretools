#!/bin/sh
# Update the list of packages
apt-get update
# Install pre-requisite packages.
apt-get install -y wget apt-transport-https software-properties-common
# Download the Microsoft repository GPG keys
wget -q "https://packages.microsoft.com/config/ubuntu/$(lsb_release -rs)/packages-microsoft-prod.deb"
# Register the Microsoft repository GPG keys
dpkg -i packages-microsoft-prod.deb
# Update the list of packages after we added packages.microsoft.com
apt-get update
# Install PowerShell
apt-get install -y powershell
