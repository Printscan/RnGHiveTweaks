#!/usr/bin/env bash
# Usage: nvidia-oc delay|log|stop|reset|nocolor|quiet
# internal: delayed


OC_LOG=/var/log/nvidia-oc.log
OC_TIMEOUT=120
NVS_TIMEOUT=10
NVML_TIMEOUT=10
MAX_DELAY=300
MIN_DELAY=30
# apply without delay
NO_DELAY=10
PILLMEM=-1000
LOWMEM=-3000
    
MIN_FIXCLOCK=500 # the above value is treated as fixed

#NO_X=1

export DISPLAY=":0"


[[ -f $RIG_CONF ]] && source $RIG_CONF
set -o pipefail

n=`gpu-detect NVIDIA`
if [[ $n -eq 0 ]]; then
    #echo "No NVIDIA GPU detected"
    exit 0
fi

[[ "$1" != "nocolor" ]] && source colors

if [[ "$1" == "log" ]]; then
    [[ ! -f $OC_LOG ]] && echo "${YELLOW}$OC_LOG does not exist${NOCOLOR}" && ex
    cat $OC_LOG 2>/dev/null && echo -e "\n${GRAY}=== $OC_LOG === $( stat -c %y $
    exit
fi


print_array() {
    local desc=$1
    local arr=($2)
    local align=10
    local pad=5
    printf "%-${align}s :" "$desc"
    for item in "${arr[@]}"
    do
        printf "%${pad}s" "$item"
    done
    printf "\n"
}


apply_settings() {
    local args="$1"
    local exitcode
    local result
    [[ -z "$args" ]] && return 0
    echo -n "${RED}" # set color to red
    result=`timeout --foreground -s9 $NVS_TIMEOUT nvidia-settings $args 2>&1 | g
    exitcode=$?
    [[ "$result" =~ ERROR: ]] && exitcode=100
    if [[ $exitcode -eq 0 ]]; then
        echo "${NOCOLOR}$result"
    else
        [[ ! -z "$result" ]] && echo "$result"
        [[ $exitcode -ge 124 ]] && echo "nvidia-settings failed by timeout (exit
    fi
    return $exitcode
}


apply_nvml() {
    local args="$1"
    local exitcode
    local result
    [[ -z "$args" ]] && return 0
    echo -n "${RED}" # set color to red
    result=`timeout --foreground -s9 $NVML_TIMEOUT nvtool -q --nodev $args`
    exitcode=$?
    if [[ $exitcode -eq 0 ]]; then
        [[ "$result" =~ "was already set" ]] && echo "${GRAY}$result${NOCOLOR}"
    else
        [[ ! -z "$result" ]] && echo "$result"
        [[ $exitcode -ge 124 ]] && echo "nvtool failed by timeout (exitcode=$exi
    fi
    return $exitcode
}


apply_mem() {
    [[ $POWERMIZER -ne 2 || ! -f $GPU_DETECT_JSON ]] && return 1
    readarray -t NAMES < <( jq -r -c '.[] | select(.brand == "nvidia") | .name'
    local args=""
    for (( i=0; i < ${#NAMES[@]}; i++ )); do
        [[ "${NAMES[i]}" =~ CMP ]] && args+="--index $i --setmem ${1:-810} "
    done
    apply_nvml "$args" >/dev/null
}


# do not run OC simultaneously
if [[ "$2" != "internal" ]]; then
    if [[ "$1" == "delay" ]]; then
        [[ -f $NVIDIA_OC_CONF ]] && source $NVIDIA_OC_CONF
        apply_mem 0
        # exit if no delay is set. OC is already applied
        [[ $RUNNING_DELAY -le 0 ]] &&
            echo "${YELLOW}No delay is set, exiting${NOCOLOR}" &&
            exit 0
    fi
    readarray -t pids < <( pgrep -f "timeout .*$OC_LOG" )
    for pid in "${pids[@]}"; do
        echo -e "${BYELLOW}Killing running nvidia-oc ($pid)${NOCOLOR}\n"
        # timeout process PID is equal to the PGID, so using it to kill process
        kill -- -$pid
    done
fi

# just exit here
if [[ "$1" == "stop" ]]; then
    [[ -f $NVIDIA_OC_CONF ]] && source $NVIDIA_OC_CONF
    apply_mem
    exit 0
fi


[[ -f /run/hive/NV_OFF ]] &&
    echo "${YELLOW}NVIDIA driver is disabled, exiting${NOCOLOR}" &&
    exit 0

[[ $MAINTENANCE == 2 ]] &&
    echo "${YELLOW}Maintenance mode enabled, exiting${NOCOLOR}" &&
    exit 1


# start main OC with timeout and logging
if [[ "$2" != "internal" ]]; then
    trap "echo -n $NOCOLOR" EXIT
    timeout --foreground -s9 $OC_TIMEOUT bash -c "set -o pipefail; $0 \"$1\" int
    exitcode=$?
    if [[ $exitcode -ne 0 && $exitcode -ne 143 ]]; then
        echo "${RED}ERROR: NVIDIA OC failed${NOCOLOR}"
        [[ "$1" != "quiet" ]] && cat $OC_LOG | message error "NVIDIA OC failed"
    fi
    exit $exitcode
fi


date
echo -e "\nDetected $n NVIDIA cards\n"

# check for running X server
[[ $NO_X -eq 0 ]] && hivex status >/dev/null && USE_X=1 || USE_X=0
#hivex status >/dev/null || echo -e "${RED}ERROR: X Server is not running! Some


if [[ "$1" == "reset" ]]; then
    echo -e "${YELLOW}Resetting OC to defaults${NOCOLOR}\n"
else
    [[ ! -f $NVIDIA_OC_CONF ]] &&
        echo "${YELLOW}$NVIDIA_OC_CONF does not exist, exiting${NOCOLOR}" &&
        exit 0
    source $NVIDIA_OC_CONF
fi

if [[ ! -f $GPU_DETECT_JSON ]]; then
    gpu_detect_json=`gpu-detect listjson`
else
    gpu_detect_json=$(< $GPU_DETECT_JSON)
fi


idx=0
while IFS=";" read busid brand name mem vbios plim_max plim_min plim_def fan_cnt
    BUSID[idx]="$busid"
    BRAND[idx]="$brand"
    NAME[idx]="$name"
    RAM[idx]="$mem"
    VBIOS[idx]="$vbios"
    PLMAX[idx]="$plim_max"
    PLMIN[idx]="$plim_min"
    PLDEF[idx]="$plim_def"
    FAN_CNT[idx]="${fan_cnt:-1}"
    ((idx++))
done < <( echo "$gpu_detect_json" | jq -r -c '.[] | select(.brand == "nvidia" or


n=${#BUSID[@]}
if [[ $n -eq 0 ]]; then
    echo -e "${RED}No cards available for OC!\n${NOCOLOR}Please check BIOS setti
    exit 1
fi


[[ $OHGODAPILL_ENABLED -eq 1 && $OHGODAPILL_START_TIMEOUT -lt 0 ]] && PILLFIX=1

# delay is applied on every miner start
MSG=
NEED_DELAY=0
DELAY=$RUNNING_DELAY
[[ $DELAY -lt $NO_DELAY ]] && DELAY=0
if [[ $DELAY -gt 0 && "$1" != "delay" && "$1" != "delayed" ]]; then
    MSG=$'\n'"  ${YELLOW}Use ${BYELLOW}nvidia-oc delay${YELLOW} to apply OC with
    DELAY=0
fi
if [[ "$1" == "delayed" && $DELAY -gt 0 ]]; then
    [[ $DELAY -lt $MIN_DELAY ]] && DELAY=$MIN_DELAY
    [[ $MAX_DELAY -gt 0 && $DELAY -gt $MAX_DELAY ]] &&
        echo -e "${YELLOW}Limiting delay to ${MAX_DELAY} secs${NOCOLOR}" &&
        DELAY=$MAX_DELAY
    echo -e "${CYAN}Waiting $DELAY secs before applying...${NOCOLOR}\n"
    sleep $DELAY
    DELAY=0
    [[ $PILLFIX -eq 1 ]] && PILLFIX=-1 # Pill fix is already applied
else
    pgrep --full nvidia-persistenced > /dev/null || nvidia-persistenced --persis
    # kill Pill if running
    pkill -f '/hive/opt/ohgodapill/run.sh'
    pkill -f '/hive/opt/ohgodapill/OhGodAnETHlargementPill-r2'
fi

[[ -f "$BUSID_FILE" ]] && source $BUSID_FILE

PARAMS=(CLOCK LCLOCK MEM LMEM PLIMIT FAN OHGODAPILL_ARGS)

# pad arrays
for param in "${PARAMS[@]}"; do
    [[ -z ${!param} ]] && continue
    declare -n ref_arr="${param}"
    ref_arr=( ${!param} )
    for ((i=${#ref_arr[@]}; i < n; i++)); do
        ref_arr[i]="${ref_arr[-1]}" # use last element of initial array
    done
done

print_array "GPU BUS ID" "${BUSID[*]/:00\.0}"
for param in "${PARAMS[@]}"; do
    arr="${param}[*]"
    [[ -z "${!arr}" ]] && continue
    print_array "$param" "${!arr}"
done

#[[ "${FAN_CNT[*]}" =~ [02-9] ]] && print_array "FAN COUNT" "${FAN_CNT[*]}"

# Use "pill cmd line params" as nvs clock in combination with fixed clock for be
[[ -z $OHGODAPILL_ENABLED && -z $OHGODAPILL_START_TIMEOUT && $OHGODAPILL_ARGS =~

echo

[[ $DEF_FIXCLOCK -ne 0 ]] && echo "NVS CLOCK:" "$DEF_FIXCLOCK"

apply_nvml " --forcestate ${FORCESTATE:-0}" # set 0 by default

AUTOFAN_ENABLED=$( [[ `pgrep -cf "/autofan run"` -gt 0 && -f $AUTOFAN_CONF ]] &&

if [[ $USE_X -eq 1 ]]; then
    echo -n "${RED}" # set color to red
    nvquery=`timeout --foreground -s9 $NVS_TIMEOUT nvidia-settings -q GPUPerfMod
                 -q GPUPowerMizerMode -q GPULogoBrightness -q GPUTargetFanSpeed
    exitcode=$?
    if [[ $exitcode -ge 124 ]]; then
        echo "NVS query error: nvidia-settings failed by timeout (exitcode=$exit
    elif [[ $exitcode -ne 0 ]]; then
        echo "(exitcode=$exitcode)"
    fi
    echo -n "${NOCOLOR}"
    nvparams="${nvquery//Attribute/$'\n'}"
fi


fan_idx=0
exitcode=0
index=0

for (( i=0; i < n; i++ )); do
    args=""

    name="${NAME[i]/NVIDIA /}"

    echo ""

    if [[ "${BRAND[i]}" != "nvidia" ]]; then
        echo "${YELLOW}===${NOCOLOR} GPU ${CYAN}-${NOCOLOR}, ${PURPLE}${BUSID[i]
        continue
    fi

    echo "${YELLOW}===${NOCOLOR} GPU ${CYAN}$index${NOCOLOR}, ${PURPLE}${BUSID[i

    if [[ "${PLIMIT[i]}" == 1 ]]; then
        echo "  ${BYELLOW}GPU is disabled${NOCOLOR}"

        apply_nvml "-i $index --setmem 810" >/dev/null
        [[ $USE_X -eq 1 && `echo "$nvparams" | grep -oP "'GPUPowerMizerMode'.*\[
            apply_settings " -a [gpu:$index]/GPUPowerMizerMode=2" >/dev/null

        ((index++))
        continue
    fi

    pldef="${PLDEF[i]%%[!0-9]*}"
    [[ -z "${PLIMIT[i]}" ]] && PLIMIT[i]=0

    apply_nvml "-i $index --setpl ${PLIMIT[i]}" || exitcode=$?

    if [[ ${CLOCK[i]} -lt $MIN_FIXCLOCK ]]; then
        apply_nvml "-i $index --setclocks ${LCLOCK:-0}" || exitcode=$?
        IFS=' ' read -r -a array2 <<< "$OHGODAPILL_ARGS"
        nvtool -i $i --setclocks "${CLOCK[i]}" --setcoreoffset "${array2[i]}"
    else
        IFS=' ' read -r -a array2 <<< "$OHGODAPILL_ARGS"
        nvtool -i $i --setclocks "${CLOCK[i]}" --setcoreoffset "${array2[i]}"
        CLOCK[i]=${DEF_FIXCLOCK:-0} || exitcode=$?
    fi

    if [[ $USE_X -eq 1 ]]; then
        x=`echo "$nvparams" | grep -oP "'GPUPerfModes'.*\[gpu\:$index\].* perf=\
        if [[ -z "$x" ]]; then
            x=3 # default
            if   [[ ${NAME[i]} =~ "RTX" ]]; then x=4
            elif [[ ${NAME[i]} =~ "P106-090" || ${NAME[i]} =~ "P104-100" || ${NA
            elif [[ ${NAME[i]} =~ "1660 Ti"  || ${NAME[i]} =~ "1660 SUPER" || ${
            elif [[ ${NAME[i]} =~ "P106-100" || ${NAME[i]} =~ "1050" || ${NAME[i
            fi
            echo "  ${GRAY}Max Perf mode: $x${NOCOLOR}"
        else
            echo "  ${GRAY}Max Perf mode: $x (auto)${NOCOLOR}"
        fi
    fi

    [[ -z "${CLOCK[i]}" ]] && CLOCK[i]=0
    # if delay is set reset clocks for the first time (except 1080* in Pill Fix
    [[ ${CLOCK[i]} -gt 0 && $DELAY -gt 0 && ($PILLFIX -eq 0 || ! "${NAME[i]}" =~
    if [[ $USE_X -eq 1 ]]; then
        if [[ `echo "$nvparams" | grep -oP "'GPUGraphicsClockOffset'.*\[gpu\:$in
            echo "  ${GRAY}Attribute 'GPUGraphicsClockOffset' was already set to
        else
            args+=" -a [gpu:$index]/GPUGraphicsClockOffset[$x]=${CLOCK[i]}"
        fi
    else
        apply_nvml "-i $index --setcoreoffset ${CLOCK[i]}" || exitcode=$?
    fi


    [[ -z "${MEM[i]}" ]] && MEM[i]=0
    # if delay is set reset clocks for the first time (except 1080* in Pill Fix
    [[ $PILLFIX -eq 1 && "${NAME[i]}" =~ 1080 && ${MEM[i]} -gt $PILLMEM ]] && ME
    [[ $MEMCLOCK -gt 0 && $DELAY -gt 0 ]] && MEMCLOCK=0 && NEED_DELAY=1
    [[ $MEMCLOCK == $LOWMEM ]] && MEMCLOCK=0
    if [[ $USE_X -eq 1 ]]; then
        value=`echo "$nvparams" | grep -oP "'GPUMemoryTransferRateOffset'.*\[gpu
        if (( MEMCLOCK <= value+1 && MEMCLOCK >= value-1 )); then
            echo "  ${GRAY}Attribute 'GPUMemoryTransferRateOffset' was already s
        else
            args+=" -a [gpu:$index]/GPUMemoryTransferRateOffset[$x]=$MEMCLOCK"
        fi
    else
        apply_nvml "-i $index --setmemoffset $MEMCLOCK" || exitcode=$?
    fi


    if [[ ${MEM[i]} == $LOWMEM ]]; then
        apply_nvml "-i $index --setmem 810" || exitcode=$?
    elif [[ ! -z ${LMEM[i]} ]]; then
        apply_nvml "-i $index --setmem ${LMEM}" || exitcode=$?
    elif [[ ! -z ${DEF_MEMCLOCK} ]]; then
        apply_nvml "-i $index --setmem ${DEF_MEMCLOCK}"
    else
        apply_nvml "-i $index --setmem 0" >/dev/null
    fi


    [[ $USE_X -eq 1 && `echo "$nvparams" | grep -oP "'GPUPowerMizerMode'.*\[gpu\
        args+=" -a [gpu:$index]/GPUPowerMizerMode=${POWERMIZER:-1}"

    if [[ $USE_X -eq 1 ]]; then
        fans_count="${FAN_CNT[i]}"
        if [[ $fans_count -gt 0 ]]; then
            [[ -z "${FAN[i]}" ]] && FAN[i]=0
            if [[ `echo "$nvparams" | grep -oP "'GPUTargetFanSpeed'.*\[gpu\:$ind
                echo "  ${GRAY}Attribute 'GPUTargetFanSpeed' was already set to
            else
                if [[ ${FAN[i]} == 0 ]]; then
                    [[ "$AUTOFAN_ENABLED" != 1 ]] &&
                        args+=" -a [gpu:$index]/GPUFanControlState=0"
                else
                    args+=" -a [gpu:$index]/GPUFanControlState=1"
                    for (( f=fan_idx; f < fan_idx + fans_count; f++ )); do
                        args+=" -a [fan:$f]/GPUTargetFanSpeed=${FAN[i]}"
                    done
                fi
            fi
            fan_idx=$(( fan_idx + fans_count ))
        fi
    elif [[ ${FAN_CNT[i]} -gt 0 && ( ${FAN[i]} -ne 0 || "$AUTOFAN_ENABLED" != 1
        apply_nvml "-i $index --setfan ${FAN[i]:-0}" || exitcode=$?
    fi


    if [[ $USE_X -eq 1 ]]; then
        brightness=`echo "$nvparams" | grep -oP "'GPULogoBrightness'.*\[gpu\:$in
        [[ ! -z "$brightness" && ! -z "$LOGO_BRIGHTNESS" && "$brightness" != "$L
            args+=" -a [gpu:$index]/GPULogoBrightness=$LOGO_BRIGHTNESS"

        apply_settings "$args" || exitcode=$?
    elif [[ ! -z "$LOGO_BRIGHTNESS" ]]; then
        apply_nvml "-i $index --setlogo $LOGO_BRIGHTNESS" || exitcode=$?
    fi
    ((index++))
done

# start Pill if needed
if [[ "$OHGODAPILL_ENABLED" -eq 1 && $PILLFIX -ne -1 && ($NEED_DELAY -eq 0 || $P
    echo
    echo "${YELLOW}===${NOCOLOR} Starting OhGodAnETHlargementPill ${YELLOW}=== `
    sleep 1

    if [[ $PILLFIX -eq 1 ]]; then
        # phase 0
        /hive/opt/ohgodapill/OhGodAnETHlargementPill-r2 > /var/run/hive/ohgodapi
        sleep 1
        #pkill -f '/hive/opt/ohgodapill/OhGodAnETHlargementPill-r2' >/dev/null
        kill $!
        wait $! 2>/dev/null

        for phase in {1..2}; do
            args=
            index=0
            for (( i=0; i < n; i++ )); do
                [[ "${BRAND[i]}" != "nvidia" ]] && continue
                if [[ "${NAME[i]}" =~ 1080 && ${MEM[i]} -ne 0 && ${MEM[i]} -gt $
                    [[ $phase -eq 1 ]] && MEMCLOCK=$PILLMEM || MEMCLOCK=${MEM[i]
                    [[ $USE_X -eq 1 ]] &&
                        args+=" -a [gpu:$index]/GPUMemoryTransferRateOffset[3]=$
                        args+=" -i $index --setmemoffset $MEMCLOCK"
                fi
                ((index++))
            done
            if [[ ! -z "$args" ]]; then
                echo -e "\n  ${GRAY}Phase ${phase}${NOCOLOR}"
                if [[ $USE_X -eq 1 ]]; then
                    apply_settings "$args" || exitcode=$?
                else
                    apply_nvml "$args" || exitcode=$?
                fi
                sleep 1
            fi
        done
    fi

    echo -e "\n  ${WHITE}Pill will be ready in ${OHGODAPILL_START_TIMEOUT#-} sec
    nohup /hive/opt/ohgodapill/run.sh $OHGODAPILL_ARGS > /dev/null 2>&1 &
fi

# apply delay only if some settings were reset
if [[ $NEED_DELAY -gt 0 && $DELAY -gt 0 ]]; then
    echo
    echo "  ${WHITE}Full OC will be applied in $DELAY secs${NOCOLOR}"

    # append to log file
    nohup timeout -s9 $(( OC_TIMEOUT + DELAY )) \
        bash -c "set -o pipefail; nvidia-oc delayed internal 2>&1 | tee -a $OC_L
fi

echo "$MSG"

exit $exitcode
