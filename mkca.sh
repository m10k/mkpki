#!/bin/bash

# mkca.sh - Set up a CA for IPsec VPNs within seconds
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

	opt_add_arg "r" "root"         "v"  "$PWD" "The CA's root directory (default: $PWD)"
	opt_add_arg "l" "lifetime"     "v"  3650   "CA lifetime in days (default: 3650)"
	opt_add_arg "s" "key-length"   "v"  4096   "RSA key length (default: 4096)"
	opt_add_arg "C" "country"      "rv" ""     "The country of the CA"
	opt_add_arg "O" "organization" "rv" ""     "The organization of the CA"
	opt_add_arg "N" "common-name"  "rv" ""     "The common name of the CA"

	if ! opt_parse "$@"; then
		return 1
	fi

	root=$(opt_get "root")
	lifetime=$(opt_get "lifetime")
	key_length=$(opt_get "key-length")
	country=$(opt_get "country")
	organization=$(opt_get "organization")
	common_name=$(opt_get "common-name")

	if ! ipsec_ca_init "$root"         \
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
