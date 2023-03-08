#!/usr/bin/env bash

#######################
# Functions
#######################

LOGTAIL=""

get_log_tail(){
  LOGTAIL=`tail -n 200 $log_name`
}

get_cards_hashes(){
#05-12-2022 21:41:25 [GPU 0] 220005386 STEPS (+31872188) | 87.57540s | FLOPS = 363.940 kFLOPS | HR = 21.506 H | AVG(O)n ^ 1.03324 | CIRCUIT SIMULATION (0.15h)
  hs=''; local t_hs=0
  local i=0
  for (( i=0; i < ${GPU_COUNT_NVIDIA}; i++ )); do
    t_hs=`echo "$LOGTAIL" | grep "\[GPU $i\]" | grep "HR = " | tail -n 1 | cut -f 18 -d " " -s`
    hs+="$t_hs "
  done
}


get_total_hashes(){
#05-12-2022 21:41:25 [GPU *] 321048393 STEPS (+35087218) | 105.25s | FLOPS = 333.371 kFLOPS | HR = 21.506 H | AVG(O)n ^ 1.06397
  khs=`echo "$LOGTAIL" | grep "\[GPU \*\]" | grep "HR = " | tail -n 1 | cut -f 18 -d " " -s | awk '{ printf($1/1000) }'` || khs=0
}

get_shares(){
#05-12-2022 21:45:19 [STRATUM] SHARE ACCEPTED BY POOL (19/0)
  local t_sh=
  t_sh=`echo "$LOGTAIL" | grep "SHARE ACCEPTED" | tail -n 1 | cut -f 8 -d " " -s`
  ac=`echo "${t_sh}" | cut -d "(" -f 2 -s | cut -f 1 -d "/" -s`
  rj=`echo "${t_sh}" | cut -f 2 -d "/" -s | cut -d ")" -f 1 -s`
}

get_miner_uptime(){
  local a=0
  let a=`stat --format='%Y' $log_name`-`stat --format='%Y' $conf_name`
  echo $a
}

get_log_time_diff(){
  local a=0
  let a=`date +%s`-`stat --format='%Y' $log_name`
  echo $a
}

get_sol(){
  t_sol=`echo "$LOGTAIL" | grep -A 50 "SOLUTION FOUND"`
  [[ ! -z "$t_sol" ]] && echo "$t_sol" | message ok "solution found"
}

get_json_stats(){
  STATS=${CUSTOM_LOG_BASENAME}.json
  now=$(date +%s)
  upd=$(stat -c %Y $STATS 2>/dev/null)
  if (( $? == 0 && upd + 180 > now )); then
    readarray -t arr < <(jq -rc '.ver, .avg/1000, .hr, .ac, .rj, .uptime, .gpu, .bus_numbers' $STATS)
    ver=${arr[0]}
    khs=${arr[1]}
    hs=${arr[2]}
    ac=${arr[3]}
    rj=${arr[4]}
    uptime=${arr[5]}
    hash_arr="${arr[6]}"
    bus_numbers="${arr[7]}"
    #khs=$( echo "$hs" | awk '{ printf $1/1000}')

    readarray -t gpu_stats < <(jq --slurp -r -c '.[] | .busids, .brand, .temp, .fan | join(" ")' $GPU_STATS_JSON 2>/dev/null)
    busids=(${gpu_stats[0]})
    brands=(${gpu_stats[1]})
    temps=(${gpu_stats[2]})
    fans=(${gpu_stats[3]})
    count=${#busids[@]}

    # match by busid
    readarray -t busid_arr < <(echo "$bus_numbers" | jq -rc '.[]') # 1 2 3
    fan_arr=()
    temp_arr=()
    for(( i=0; i < count; i++ )); do
      [[ "${brands[i]}" != "nvidia" ]] && continue
      [[ ! "${busids[i]}" =~ ^([A-Fa-f0-9]+): ]] && continue
      [[ ! " ${busid_arr[@]} " =~ \ $((16#${BASH_REMATCH[1]}))\  ]] && continue
      temp_arr+=(${temps[i]})
      fan_arr+=(${fans[i]})
    done

    fan=`printf '%s\n' "${fan_arr[@]}"  | jq -cs '.'`
    temp=`printf '%s\n' "${temp_arr[@]}"  | jq -cs '.'`

  else
    hash_arr="null"
    bus_numbers="null"
    khs=0
    ac=0
    rj=0
    ver="$CUSTOM_VERSION"
    uptime=0
    temp="null"
    fan="null"
    echo "No stats json"
  fi

  stats=$(jq -n --arg ac "$ac" --arg rj "$rj" --arg algo "$algo" --argjson bus_numbers "$bus_numbers" --argjson hs "$hash_arr" \
          --arg uptime "$uptime" --arg ver "$ver" --argjson temp "$temp" --argjson fan "$fan" \
          '{hs_units: "hs", $hs, $algo, $ver, $uptime, $bus_numbers, $fan, $temp, ar:[$ac|tonumber,$rj|tonumber]}')
}


#######################
# MAIN script body
#######################

. /hive/miners/custom/dynexsolve/h-manifest.conf

local algo="cryptonight"

stats=""
khs=0

if true; then
  get_json_stats
else
  local temp=$(jq '.temp' <<< $gpu_stats)
  local fan=$(jq '.fan' <<< $gpu_stats)

  temp=$(jq -rc ".$nvidia_indexes_array" <<< $temp)
  fan=$(jq -rc ".$nvidia_indexes_array" <<< $fan)

  local log_name="$CUSTOM_LOG_BASENAME.log"
  local conf_name="$CUSTOM_CONFIG_FILENAME"

  local ac=0
  local rj=0

  [[ -z $GPU_COUNT_NVIDIA ]] && GPU_COUNT_NVIDIA=`gpu-detect NVIDIA`

  # Calc log freshness
  local diffTime=$(get_log_time_diff)
  local maxDelay=120

  # echo $diffTime

  # If log is fresh the calc miner stats or set to null if not
  if [[ "$diffTime" -lt "$maxDelay" ]]; then
    get_log_tail
    get_cards_hashes                 # hashes
    get_total_hashes                 # total hashes
    get_shares                       # accepted, rejected
    local hs_units='hs'              # hashes utits
    local uptime=$(get_miner_uptime) # miner uptime

    get_sol

    # make JSON
    #--argjson hs "`echo ${hs[@]} | tr " " "\n" | jq -cs '.'`" \

    stats=$(jq -nc \
        --argjson hs "`echo ${hs[@]} | tr " " "\n" | jq -cs '.'`" \
        --arg hs_units "$hs_units" \
        --argjson temp "`echo ${temp[@]} | tr " " "\n" | jq -cs '.'`" \
        --argjson fan "`echo ${fan[@]} | tr " " "\n" | jq -cs '.'`" \
        --arg ac "$ac" --arg rj "$rj" \
        --arg uptime "$uptime" \
        --arg algo "$algo" \
        --arg ver "$CUSTOM_VERSION" \
        '{$hs, $hs_units, $temp, $fan, $uptime, $algo, ar: [$ac, $rj], $ver}')
  fi
fi

# debug output
#echo temp:  $temp
#echo fan:   $fan
#echo stats: $stats
#echo khs:   $khs
