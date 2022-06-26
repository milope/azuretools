# Template: Create a Storage Account with a Private Endpoint

This is a very simple template to show how to create an Azure Storage Account
with a Private Endpoint for its Blob service.

## Parameters

1. **ResourcePrefix**: The resource prefix is used as a prefix for all
resources deployed (when applicable).
2. **Location**: Override the location for all the resources. Default: The
resource group's location.

## Resources

1. **A Virtual Network**: The Virtual Network used for the private endpoint
subnet.
2. **A Storage Account**: The Storage Account to deploy. This is hardcoded to
be a StorageV2 kind with Standard_LRS queue, Hot tier.
3. **Private Endpoint**: The private endpoint will be created for the Blob
service of the Azure Storage account.
4. **Private DNS Zone**: The private DNS zone will be for the
privatelink.blob.core.windows.net DNS record. The idea is that private VMs
would resolve the *storageAccountName*.blob.core.windows.net DNS as a private
IP. We use this private DNS zone to achieve this result.
5. **Private DNS Zone Link**: To successfully use the Private DNS zone, it must
be associated to the Virtual Network. This resource achieves this result.
6. **Private DNS Zone Group**: I am not completely sure how this resources
works, but it may be the resource that completes the automatic creation of the
A record with the *storageAccountName* resource as this template does not
explicitly create an A record in the privatelink.blob.core.windows.net DNS
zone.

## License/Disclaimer

Copyright © 2022 Michael Lopez

Permission is hereby granted, free of charge, to any person obtaining a copy of
this software and associated documentation files (the “Software”), to deal in
the Software without restriction, including without limitation the rights to
use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies
of the Software, and to permit persons to whom the Software is furnished to do
so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED “AS IS”, WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.

`Tags: milope, templates, storage, azure, private DNS, DNS, networking,
private endpoint`
