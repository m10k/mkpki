#!/bin/bash

# mkcert.sh - Generate server/client certificates for IPsec VPNs
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

main() {
	local root
	local lifetime
	local key_length
	local country
	local organization
	local common_name
	local -i client
	local generator

	opt_add_arg "r" "root"         "v"  "$PWD" "The CA's root directory (default: $PWD)"
	opt_add_arg "l" "lifetime"     "v"  3650   "CA lifetime in days (default: 3650)"
	opt_add_arg "s" "key-length"   "v"  4096   "RSA key length (default: 4096)"
	opt_add_arg "C" "country"      "rv" ""     "The subject country"
	opt_add_arg "O" "organization" "rv" ""     "The subject organization"
	opt_add_arg "N" "common-name"  "rv" ""     "The subject common name"
	opt_add_arg "c" "client"       ""   0      "Subject is a client (default: server)"

	if ! opt_parse "$@"; then
		return 1
	fi

	root=$(opt_get "root")
	lifetime=$(opt_get "lifetime")
	key_length=$(opt_get "key-length")
	country=$(opt_get "country")
	organization=$(opt_get "organization")
	common_name=$(opt_get "common-name")
	client=$(opt_get "client")

	if (( client == 0 )); then
		generator=ipsec_ca_generate_server_cert
	else
		generator=ipsec_ca_generate_client_cert
	fi

	if ! "$generator" "$root"         \
	                  "$country"      \
	                  "$organization" \
	                  "$common_name"  \
	                  "$lifetime"     \
	                  "$key_length"; then
		return 1
	fi

	return 0
}

{
	if ! . toolbox.sh; then
		exit 1
	fi

	if ! include "log" "opt" "ipsec"; then
		exit 1
	fi

	main "$@"
	exit "$?"
}
