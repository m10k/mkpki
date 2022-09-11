# mkpki - Certificate management and configuration of IPsec IKEv2 VPNs

This is a collection of tools that are meant to support installations of
IPsec IKEv2 VPNs using EAP-TLS with certificates for mutual authentication.

To use it, first you need to set up a new certificate authority:

    mkca --country      "DE"         \
         --organization "My company" \
         --common-name  "CA name"


## Setting up a server

Next, you need to generate a certificate for the VPN server:

    mkcert --country      "DE"              \
           --organization "My company"      \
           --common-name  "vpn.example.org"

Now you can use `exportcert` to generate a shell script that will configure
the VPN server.

    exportcert --common-name "vpn.example.org" \
               --server      "vpn.example.org" > server-setup.sh

Executing this script on a Linux box will configure it to act as an IPsec VPN server,
assuming strongswan is installed and the running kernel has IPsec support.


## Setting up a client

The same two commands can be used to generate a certificate for a client and export a
script that will configure the client.

    mkcert --client                         \
           --country      "DE"              \
           --organization "My company"      \
           --common-name  "user@example.org"

    exportcert --common-name "user@example.org" \
               --server      "vpn.example.org"  > client-setup.sh


### iPhone and other iOS clients

The `exportcert` command can also export a MobileConfig file for use with iPhones and
other Apple devices. Since EAP-TLS cannot be configured in the iPhone settings, you will
want to use this if you intend to connect an iPhone to your VPN.

    exportcert --iphone                         \
               --common-name "user@example.org" \
               --server      "vpn.example.org"  > iphone.mobileconfig

Copying the file to an iPhone and opening it in the Files application will allow you to
install the profile and the contained certificates in the settings application.
