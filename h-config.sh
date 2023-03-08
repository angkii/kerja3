#!/usr/bin/env bash
# This code is included in /hive/bin/custom function

[[ -z $CUSTOM_TEMPLATE ]] && echo -e "${YELLOW}CUSTOM_TEMPLATE is empty${NOCOLOR}" && return 1
[[ -z $CUSTOM_URL ]] && echo -e "${YELLOW}CUSTOM_URL is empty${NOCOLOR}" && return 1

local pool=`head -n 1 <<< "$CUSTOM_URL"`
grep -q ":" <<< $pool
[[ $? -ne 0 ]] && echo -e "${YELLOW}No port set in CUSTOM_URL. Should be HOST:PORT${NOCOLOR}" && return 1

host=`echo "$pool" | cut -d ":" -f 1`
port=`echo "$pool" | cut -d ":" -f 2`

conf=" -mining-address ${CUSTOM_TEMPLATE} -stratum-url $host -stratum-port $port "
[[ ! -z ${CUSTOM_PASS} ]] && conf+=" -stratum-password ${CUSTOM_PASS} "

[[ ! $CUSTOM_USER_CONFIG =~ '-deviceid' ]] && conf+=" -multi-gpu"
conf+=" ${CUSTOM_USER_CONFIG} -no-cpu -skip -stats ${CUSTOM_LOG_BASENAME}.json"

[[ -z $CUSTOM_CONFIG_FILENAME ]] && echo -e "${RED}No CUSTOM_CONFIG_FILENAME is set${NOCOLOR}" && return 1
echo "$conf" > $CUSTOM_CONFIG_FILENAME

