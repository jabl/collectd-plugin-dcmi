#!/bin/bash

# Fetch power consumption and inlet temperature, forward it to collectd
#
# Copyright (C) 2016-2021  Janne Blomqvist
#
# SPDX-License-Identifier: Apache-2.0

HOSTNAME="${COLLECTD_HOSTNAME:-$(hostname -f)}"
INTERVAL="${COLLECTD_INTERVAL:-60}"

# In principle DCMI is nice in that it provides a tighter specified subset of IPMI.
# For power consumption, this seems to work.
# However, for temperature readings, in practice:
# - some systems report incorrect record id's with
#   ipmi-dcmi --get-dcmi-sensor-info
# - others don't report at all.
# - Yet others report errors for
#   ipmitool dcmi get_temp_reading
# - ipmi-sensors generally works but different systems have different
#   sensors and different sensor names for the equivalent sensors. In
#   the end, we're only interested in the inlet temperature. So first
#   try to figure out the record id of the inlet temperature sensor.

# Note: collectd metric names should follow
# https://collectd.org/wiki/index.php/Naming_schema 
# See /usr/share/collectd/types.db for list of builtin types

inlet_id=0
while read line
do
    IFSORIG=$IFS
    IFS=","; declare -a arr=($line)
    IFS=$IFSORIG
    id=${arr[0]}
    descr=${arr[1]}
    # HP G6 calls the inlet temperature "External Environment Temperature"
    if [[ $descr == *"Inlet"*  ||  $descr == "External Environment"* ]]; then
	inlet_id=$id
    fi
done < <(sudo ipmi-sensors --interpret-oem-data -b --shared-sensors --ignore-not-available-sensors --entity-sensor-names -t Temperature --comma-separated-output --no-header-output)


while :; do
    while read line
    do
	IFSORIG=$IFS
	IFS=":"; declare -a a1=($line)
	IFS=$IFSORIG
	a2=(${a1[1]})
	pwr=${a2[0]}
	break
    done < <(sudo ipmi-dcmi --get-system-power-statistics)
    [[ ! -z $pwr ]] && echo "PUTVAL \"$HOSTNAME/dcmi/power-current\" interval=$INTERVAL N:$pwr"

    if [[ $inlet_id -ne 0 ]]; then
	while read line
	do
	    IFSORIG=$IFS
	    IFS=","; declare -a arr=($line)
	    IFS=$IFSORIG
	    val=${arr[3]}
	    echo "PUTVAL \"$HOSTNAME/dcmi/temperature-inlet\" interval=$INTERVAL N:$val"
	done < <(sudo ipmi-sensors --interpret-oem-data -b --shared-sensors --ignore-not-available-sensors -r $inlet_id --comma-separated-output --no-header-output)
    fi

    sleep "$INTERVAL"
done
