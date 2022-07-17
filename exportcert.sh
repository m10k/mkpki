#!/bin/bash

# exportcert.sh - Export VPN client/server configurations
# Copyright (C) 2022 Matthias Kruk
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <https://www.gnu.org/licenses/>.

cert_is_client() {
	local root="$1"
	local common_name="$2"

	local cert
	local data

	cert="$root/certs/$common_name.pem"

	if ! data=$(openssl x509 -in "$cert" -noout -text); then
		log_error "Could not read certificate $cert"
		return 2
	fi

	if [[ "$data" == *"TLS Web Server Authentication, 1.3.6.1.5.5.8.2.2"* ]]; then
		return 1
	fi

	return 0
}

generate_shellscript() {
	local root="$1"
	local common_name="$2"
	local server="$3"

	local cacertpath
	local certpath
	local keypath
	local cacert
	local cert
	local key
	local target

	cacertpath="$root/cacerts/cacert.pem"
	certpath="$root/certs/$common_name.pem"
	keypath="$root/private/$common_name.pem"

	if ! cacert=$(< "$cacertpath"); then
		log_error "Could not read $cacertpath"
		return 1
	fi

	if ! cert=$(< "$certpath"); then
		log_error "Could not read $certpath"
		return 1
	fi

	if ! key=$(< "$keypath"); then
		log_error "Could not read $keypath"
		return 1
	fi

	if cert_is_client "$root" "$common_name"; then
		target="client"
	else
		target="server"
	fi

	cat <<EOF
#!/bin/bash

make_cacert() {
	cat <<ENDE
$cacert
ENDE
}

make_cert() {
	cat <<ENDE
$cert
ENDE
}

make_key() {
	cat <<ENDE
$key
ENDE
}

make_client_config() {
	cat <<ENDE
config setup
        # strictcrlpolicy=yes
        # uniqueids = no

conn %default
        ikelifetime=60m
        keylife=20m
        rekeymargin=3m
        keyingtries=1
        keyexchange=ikev2

conn $server
        leftauth=eap-tls
        left=%defaultroute
        leftid=$common_name
        leftsubnet=0.0.0.0/0
        leftcert=$common_name.pem
        leftsourceip=%config
        leftfirewall=yes
        right=$server
        rightsubnet=10.1.0.0/24
        rightauth=any
        rightid=@$server
        auto=start
        eap_identity=%identity
ENDE
}

make_server_config() {
	cat <<ENDE
config setup
        # strictcrlpolicy=yes
        # uniqueids = no

conn %default
        dpdaction=clear
        dpddelay=300s
        fragmentation=yes
        mobike=yes
        compress=yes

conn $common_name-base
        keyexchange=ikev2
        left=%any
        leftauth=pubkey
        leftid=$common_name
        leftcert=$common_name.pem
        leftsendcert=always
        leftsubnet=10.1.0.0/24
        leftfirewall=yes
        right=%any
        rightsourceip=10.2.0.0/24
        rightdns=10.1.0.1

conn $common_name-eaptls
        also=$common_name-base
        rightauth=eap-tls
        rightid=%any
        eap_identity=%any
        auto=add
        reauth=no
ENDE
}

add_credentials() {
	local cacert
	local cert
	local key

	cacert="/etc/ipsec.d/cacerts/cacert.pem"
	cert="/etc/ipsec.d/certs/$common_name.pem"
	key="/etc/ipsec.d/private/$common_name.pem"

	if ! make_cacert > "\$cacert"; then
		echo "Could not write CA certificate to \$cacert" 1>&2
		return 1
	fi

	if ! make_cert > "\$cert"; then
		echo "Could not write certificate to \$cert" 1>&2
		return 1
	fi

	if ! make_key > "\$key"; then
		echo "Could not write key to \$key" 1>&2
		return 1
	fi

	if ! echo " : RSA $common_name.pem" >> /etc/ipsec.secrets; then
		echo "Could not write to /etc/ipsec.secrets" 1>&2
		return 1
	fi

	return 0
}

backup_strongswan_config() {
	local timestamp
	local old
	local new

	old="/etc/ipsec.conf"

	if ! [ -e "\$old" ]; then
		return 0
	fi

	if ! timestamp=\$(date +"%s"); then
		echo "Could not make a timestamp. OOM?" 1>&2
		return 1
	fi

	new="\$old.\$timestamp"
	echo "Backing up \$old to \$new" 1>&2
	if ! mv "\$old" "\$new"; then
		echo "Could not move \$old to \$new" 1>&2
		return 1
	fi

	return 0
}

configure_strongswan() {
	if ! backup_strongswan_config; then
		return 1
	fi

	if ! make_${target}_config > "/etc/ipsec.conf"; then
		echo "Could not write to /etc/ipsec.conf" 1>&2
		return 1
	fi

	return 0
}

main() {
	if ! add_credentials ||
	   ! configure_strongswan; then
		return 1
	fi

	return 0
}

{
	main "\$@"
	exit "\$?"
}
EOF

	return 0
}

rjoin() {
	local token="$1"
	local fields=("${@:2}")

	local sep
	local i

	sep=""

	for (( i = ${#fields[@]} - 1; i >= 0; i-- )); do
		printf '%s%s' "$sep" "${fields[$i]}"
		sep="$token"
	done

	printf '\n'
}

reverse_domain() {
	local domain="$1"

	local labels

	domain="${domain//@/.}"
	IFS="." read -ra labels <<< "$domain"

	rjoin "." "${labels[@]}"
}

get_ca_name() {
	local root="$1"

	local cacert

	cacert="$root/cacerts/cacert.pem"

	if ! openssl x509 -in "$cacert" -noout -text |
	         grep -oP 'Issuer:.+CN = \K.+'; then
		log_error "Could not get CA name from $cacert"
		return 1
	fi

	return 0
}

get_ca_data() {
	local root="$1"

	local cacert

	cacert="$root/cacerts/cacert.pem"

	if ! openssl x509 -in "$cacert" -outform DER | base64 -w 0; then
		return 1
	fi

	return 0
}

get_client_pkcs12() {
	local root="$1"
	local common_name="$2"

	local clientkey
	local clientcert
	local cacert

	clientkey="$root/private/$common_name.pem"
	clientcert="$root/certs/$common_name.pem"
	cacert="$root/cacerts/cacert.pem"

	if ! openssl pkcs12 -export                     \
	                    -inkey "$clientkey"         \
	                    -in "$clientcert"           \
	                    -name "Client Certificarte" \
	                    -certfile "$cacert"         \
	                    -caname "CA Certificate" | base64 -w 0; then
		return 1
	fi

	return 0
}

generate_mobileconfig() {
	local root="$1"
	local common_name="$2"
	local server="$3"

	local config_uuid
	local profile_uuid
	local certificate_uuid
	local cacert_uuid
	local caname
	local cacert_data
	local certbundle_data
	local reverse_common_name
	local reverse_server

	if ! cert_is_client "$root" "$common_name"; then
		log_error "Cannot export server certificates as MobileConfig"
		return 1
	fi

	if ! caname=$(get_ca_name "$root"); then
		return 1
	fi

	if ! cacert_data=$(get_ca_data "$root"); then
		return 1
	fi

	if ! certbundle_data=$(get_client_pkcs12 "$root" "$common_name"); then
		return 1
	fi

	if ! reverse_common_name=$(reverse_domain "$common_name") ||
	   ! reverse_server=$(reverse_domain "$server"); then
		log_error "Could not generate identifiers for MobileConfig"
		return 1
	fi

	if ! config_uuid=$(uuidgen -r) ||
	   ! profile_uuid=$(uuidgen -r) ||
	   ! certificate_uuid=$(uuidgen -r) ||
	   ! cacert_uuid=$(uuidgen -r); then
		log_error "Could not generate UUIDs for MobileConfig"
		return 1
	fi

	cat <<EOF
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
	<dict>
		<key>PayloadDisplayName</key>
		<string>$server IPsec VPN</string>

		<key>PayloadIdentifier</key>
		<string>$reverse_server.vpn</string>

		<key>PayloadUUID</key>
		<string>$config_uuid</string>

		<key>PayloadType</key>
		<string>Configuration</string>

		<key>PayloadVersion</key>
		<integer>1</integer>

		<key>PayloadContent</key>
		<array>
			<dict>
				<key>PayloadIdentifier</key>
				<string>$reverse_server.vpn.profile</string>

				<key>PayloadUUID</key>
				<string>$profile_uuid</string>

				<key>PayloadType</key>
				<string>com.apple.vpn.managed</string>

				<key>PayloadVersion</key>
				<integer>1</integer>

				<key>UserDefinedName</key>
				<string>$server IPsec VPN</string>

				<key>VPNType</key>
				<string>IKEv2</string>

				<key>IKEv2</key>
				<dict>
					<key>RemoteAddress</key>
					<string>$server</string>

					<key>RemoteIdentifier</key>
					<string>$server</string>

					<key>LocalIdentifier</key>
					<string>$common_name</string>

					<key>ServerCertificateIssuerCommonName</key>
					<string>$caname</string>

					<key>ServerCertificateCommonName</key>
					<string>$server</string>

					<key>ExtendedAuthEnabled</key>
					<integer>1</integer>

					<key>PayloadCertificateUUID</key>
					<string>$certificate_uuid</string>

					<key>CertificateType</key>
					<string>RSA</string>

					<key>AuthenticationMethod</key>
					<string>Certificate</string>

					<key>IKESecurityAssociationParameters</key>
					<dict>
						<key>EncryptionAlgorithm</key>
						<string>AES-256</string>

						<key>IntegrityAlgorithm</key>
						<string>SHA2-256</string>

						<key>DiffieHellmanGroup</key>
						<integer>14</integer>
					</dict>

					<key>ChildSecurityAssociationParameters</key>
					<dict>
						<key>EncryptionAlgorithm</key>
						<string>AES-256</string>

						<key>IntegrityAlgorithm</key>
						<string>SHA2-256</string>

						<key>DiffieHellmanGroup</key>
						<integer>14</integer>
					</dict>
				</dict>
			</dict>
			<dict>

				<key>PayloadIdentifier</key>
				<string>$caname</string>

				<key>PayloadUUID</key>
				<string>$cacert_uuid</string>

				<key>PayloadType</key>
				<string>com.apple.security.root</string>

				<key>PayloadVersion</key>
				<integer>1</integer>

				<key>PayloadContent</key>
				<data>$cacert_data</data>
			</dict>
			<dict>
				<key>PayloadIdentifier</key>
				<string>$reverse_common_name</string>

				<key>PayloadUUID</key>
				<string>$certificate_uuid</string>

				<key>PayloadType</key>
				<string>com.apple.security.pkcs12</string>

				<key>PayloadVersion</key>
				<integer>1</integer>

				<key>PayloadContent</key>
				<data>$certbundle_data</data>
			</dict>
		</array>
	</dict>
</plist>
EOF

	return 0
}

have_cert() {
	local root="$1"
	local common_name="$2"

	local cert

	cert="$root/certs/$common_name.pem"

	if [ -e "$cert" ]; then
		return 0
	fi

	return 1
}

export_cert() {
	local root="$1"
	local common_name="$2"
	local server="$3"
	local -i iphone="$4"

	local generator

	if ! have_cert "$root" "$common_name"; then
		log_error "Have no certificates for $common_name"
		return 1
	fi

	if (( iphone == 0 )); then
		generator=generate_shellscript
	else
		generator=generate_mobileconfig
	fi

	if ! "$generator" "$root" "$common_name" "$server"; then
		return 1
	fi

	return 0
}

main() {
	local root
	local common_name
	local server
	local -i iphone

	opt_add_arg "r" "root"        "v"  "$PWD" "The CA's root directory (default: $PWD)"
	opt_add_arg "N" "common-name" "rv" ""     "The common name of the certificate to export"
	opt_add_arg "s" "server"      "rv" ""     "The hostname of the VPN server"
	opt_add_arg "i" "iphone"      ""   0      "Export as Apple MobileConfig file (default: no)"

	if ! opt_parse "$@"; then
		return 1
	fi

	root=$(opt_get "root")
	common_name=$(opt_get "common-name")
	server=$(opt_get "server")
	iphone=$(opt_get "iphone")

	if ! export_cert "$root" "$common_name" "$server" "$iphone"; then
		return 1
	fi

	return 0
}

{
	if ! . toolbox.sh; then
		exit 1
	fi

	if ! include "log" "opt"; then
		exit 1
	fi

	main "$@"
	exit "$?"
}
