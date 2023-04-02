#!/usr/bin/env bash
#edited by Palmatorro and Qwerter123
#core clocks, mem voltages and soc voltages are overrided with extended values


# GFX VDDC (Core), mV
NAVI_CVDDC_MIN=500   # Min VDDC - Gfx Core
NAVI_CVDDC_MAX=1200  # Max VDDC - Gfx Core
VEGA_CVDDC_SAFE=900  # Default fail safe voltage for Vega20
NAVI_CVDDC_SAFE=850  # Default fail safe voltage for Navi10/Navi20
# SoC VDD limits, mV
NAVI_SOC_VDD_MIN=250   # Min SoC VDD
NAVI_SOC_VDD_MAX=1200  # Max SoC VDD
# Memory Interface Controller Interface Voltage, mV
NAVI_VDDCI_MIN=500   # Min VDDCI
NAVI_VDDCI_MAX=850   # Max VDDCI
# Memory Voltage, mV
NAVI_MVDD_MIN=500   # Min MVDD
NAVI_MVDD_MAX=1450   # Max MVDD
# Clocks, MHz
VEGA_SafeCoreClock=1500
NAVI_SafeCoreClock=1400
NAVI_MinCoreClock=250
NAVI_MaxMemClock=1075   # Max memory clock

hwmondir=`realpath /sys/class/drm/card${cardno}/device/hwmon/hwmon*/`

# set Power Limit
function set_PowerLimit(){
    if [[ -n $PL && ${PL[$i]} -gt 0 ]]; then
        if [[ -e ${hwmondir}/power1_cap_max ]] && [[ -e ${hwmondir}/power1_cap ]]; then
           echo $((PL[$i]*1000000)) > ${hwmondir}/power1_cap && echo -e "Setting Power Limit to ${GREEN}${PL[$i]}W${NOCOLOR}"
        fi
    fi
}

# Set fan mode & speed
function set_FanSpeed() { 
    if [[ -n ${hwmondir} ]]; then
        if [[ ${FAN[$i]} -gt 0 && -e ${hwmondir}/pwm1 ]]; then
            [[ -e ${hwmondir}/pwm1_enable ]] && echo 1 > ${hwmondir}/pwm1_enable
            [[ -e ${hwmondir}/pwm1_max ]] && fanmax=`head -1 ${hwmondir}/pwm1_max` || fanmax=255
            [[ -e ${hwmondir}/pwm1_min ]] && fanmin=`head -1 ${hwmondir}/pwm1_min` || fanmin=0
            echo $(( FAN[i]*(fanmax - fanmin)/100 + fanmin )) > ${hwmondir}/pwm1
        else # set to auto mode
            [[ -e ${hwmondir}/pwm1_enable ]] && echo 2 > ${hwmondir}/pwm1_enable
            echo "Setting Fan speed set to Auto (HW)"
        fi
    else
        echo -e "${RED}Error: unable to get HWMON dir to set fan${NOCOLOR}"
    fi
}

function set_CoreMemOC(){
    local cclk=$1
    local mclk=$2
    local cvdd=$3

    local cdpm=$(($(cat /sys/class/drm/card"${cardno}"/device/pp_dpm_sclk | wc -l) - 1 ))
    local sdpm=$(($(cat /sys/class/drm/card"${cardno}"/device/pp_dpm_socclk | wc -l) - 1 ))
    local mdpm=$(($(cat /sys/class/drm/card"${cardno}"/device/pp_dpm_mclk | wc -l) - 1 ))
    
    # OC preparation
 #   if [[ $IS_NAVI20 -eq 0 ]]; then
    [[ $IS_BC250 -eq 0 ]] && echo 5 > /sys/class/drm/card${cardno}/device/pp_power_profile_mode 2> /dev/null
 #   fi
    [[ $IS_BC250 -eq 0 ]] && echo "manual" > /sys/class/drm/card${cardno}/device/power_dpm_force_performance_level 2> /dev/null

    # Core clock
    [[ -n $cclk && $cclk -gt 0 ]] && echo "s 1 ${cclk}" > /sys/class/drm/card${cardno}/device/pp_od_clk_voltage 2> /dev/null
    # Memory clock
    [[ -n $mclk && $mclk -gt 0 ]] && echo "m 1 ${mclk}" > /sys/class/drm/card${cardno}/device/pp_od_clk_voltage 2> /dev/null
    # Core VDDC
    [[  -z $cvdd  || $cvdd -eq 0 ]] && cvdd="${NAVI_CVDDC_SAFE}"
    if [[ $IS_NAVI20 -eq 0 ]]; then
		[[ $IS_BC250 -gt 0 ]] && lvl=0 || lvl=2
       # Vega20 and Navi10
       [[ $cclk -gt 0 && $cvdd -gt 0 ]] && echo "vc ${lvl} ${cclk} ${cvdd}" > /sys/class/drm/card${cardno}/device/pp_od_clk_voltage 2> /dev/null
    else # Navi20
       [[ $cclk -gt 0 ]] && echo "vc 2 $cclk" > /sys/class/drm/card${cardno}/device/pp_od_clk_voltage 2> /dev/null
    fi
    echo "c" > /sys/class/drm/card${cardno}/device/pp_od_clk_voltage 2> /dev/null
    # Finally, set performance states
    echo $cdpm > /sys/class/drm/card"${cardno}"/device/pp_dpm_sclk 2> /dev/null
    echo $mdpm > /sys/class/drm/card"${cardno}"/device/pp_dpm_mclk 2> /dev/null
    [[ $IS_NAVI20 -gt 0 ]] && echo $sdpm > /sys/class/drm/card"${cardno}"/device/pp_dpm_socclk 2> /dev/null
}

function vega20_get_defaults(){
    echo -e "${CYAN}Default Power Play settings from VBIOS for Vega20${NOCOLOR}"
    readarray -t data < <( python3 /hive/opt/upp2/upp.py -p $savedpp get \
        OverDrive8Table/ODSettingsMax/0 \
        OverDrive8Table/ODSettingsMax/8 \
        smcPPTable/SocketPowerLimitAc0 \
        smcPPTable/MinVoltageGfx \
        smcPPTable/MaxVoltageGfx \
        smcPPTable/MinVoltageSoc \
        smcPPTable/MaxVoltageSoc \
        smcPPTable/FreqTableSocclk/7 \
        smcPPTable/TdcLimitGfx \
        smcPPTable/TdcLimitSoc \
        OverDrive8Table/ODSettingsMin/9 \
        OverDrive8Table/ODSettingsMax/9 \
        OverDrive8Table/ODSettingsMax/14 \
        smcPPTable/FanTargetTemperature \
        smcPPTable/FreqTableUclk/3 \
        smcPPTable/FreqTableSocclk/0 \
    )

    PPT_maxCoreClk=$(( data[0] ))
    PPT_maxMemClk=$(( data[1] ))
    PPT_PL=$(( data[2] ))
    PPT_minVDDcore=$(( data[3] / 4 ))
    PPT_maxVDDcore=$(( data[4] / 4 ))
    PPT_minVDDsoc=$(( data[5] / 4 ))
    PPT_maxVDDsoc=$(( data[6] / 4 ))
    PPT_minVDDCI=$NAVI_VDDCI_MIN
    PPT_maxVDDCI=$NAVI_VDDCI_MAX
    PPT_minMVDD=1200
    PPT_maxMVDD=1250
    PPT_maxSocClk=$(( data[7] ))
    PPT_TDCgfx=$(( data[8] ))
    PPT_TDCsoc=$(( data[9] ))
    PPT_minOPL=$(( data[10] ))
    PPT_maxOPL=$(( data[11] ))
    PPT_maxTC=$(( data[12] ))
    PPT_FanTT=$(( data[13] ))
    PPT_defMemClk=$(( data[14] ))
    PPT_minSocClk=$(( data[15] ))

    echo "CORE Clock max: ${PPT_maxCoreClk}MHz, Voltage: ${PPT_minVDDcore}-${PPT_maxVDDcore}mV SOC Clock: ${PPT_minSocClk}-${PPT_maxSocClk}MHz, Voltage: ${PPT_minVDDsoc}-${PPT_maxVDDsoc}mV"
    echo "MEMORY Clock def/max: ${PPT_defMemClk}/${PPT_maxMemClk}MHz, Voltage: ${PPT_minMVDD}-${PPT_maxMVDD}mV, VDDCI: ${PPT_minVDDCI}-${PPT_maxVDDCI}mV, TC: ${PPT_maxTC}"
    echo "POWER PL: ${PPT_PL}W OV: -${PPT_minOPL}%/+${PPT_maxOPL}%, TDC GFX: ${PPT_TDCgfx}A, TDC SOC: ${PPT_TDCsoc}A, TEMP Target: ${PPT_FanTT}C"
}

function navi10_get_defaults(){
    echo -e "${CYAN}Default Power Play settings from VBIOS for Navi10${NOCOLOR}"
    readarray -t data < <( python3 /hive/opt/upp2/upp.py -p $savedpp get \
        overdrive_table/max/0 \
        overdrive_table/max/8 \
        smc_pptable/SocketPowerLimitAc/0 \
        smc_pptable/MinVoltageGfx \
        smc_pptable/MaxVoltageGfx \
        smc_pptable/MinVoltageSoc \
        smc_pptable/MaxVoltageSoc \
        smc_pptable/MemVddciVoltage/0 \
        smc_pptable/MemVddciVoltage/3 \
        smc_pptable/MemMvddVoltage/0 \
        smc_pptable/MemMvddVoltage/3 \
        smc_pptable/FreqTableSocclk/1 \
        smc_pptable/TdcLimitGfx \
        smc_pptable/TdcLimitSoc \
        overdrive_table/min/9 \
        overdrive_table/max/9 \
        overdrive_table/max/14 \
        smc_pptable/FanTargetTemperature \
        smc_pptable/FreqTableUclk/3 \
        smc_pptable/FreqTableSocclk/0 \
    )

    PPT_maxCoreClk=$(( data[0] ))
    PPT_maxMemClk=$(( data[1] ))
    PPT_PL=$(( data[2] ))
    PPT_minVDDcore=$(( data[3] / 4 ))
    PPT_maxVDDcore=$(( data[4] / 4 ))
    PPT_minVDDsoc=$(( data[5] / 4 ))
    PPT_maxVDDsoc=$(( data[6] / 4 ))
    PPT_minVDDCI=$(( data[7] / 4 ))
    PPT_maxVDDCI=$(( data[8] / 4 ))
    PPT_minMVDD=$(( data[9] / 4 ))
    PPT_maxMVDD=$(( data[10] / 4 ))
    PPT_maxSocClk=$(( data[11] ))
    PPT_TDCgfx=$(( data[12] ))
    PPT_TDCsoc=$(( data[13] ))
    PPT_minOPL=$(( data[14] ))
    PPT_maxOPL=$(( data[15] ))
    PPT_maxTC=$(( data[16] ))
    PPT_FanTT=$(( data[17] ))
    PPT_defMemClk=$(( data[18] ))
    PPT_minSocClk=$(( data[19] ))

    echo "CORE Clock max: ${PPT_maxCoreClk}MHz, Voltage: ${PPT_minVDDcore}-${PPT_maxVDDcore}mV SOC Clock: ${PPT_minSocClk}-${PPT_maxSocClk}MHz, Voltage: ${PPT_minVDDsoc}-${PPT_maxVDDsoc}mV"
    echo "MEMORY Clock def/max: ${PPT_defMemClk}/${PPT_maxMemClk}MHz, Voltage: ${PPT_minMVDD}-${PPT_maxMVDD}mV, VDDCI: ${PPT_minVDDCI}-${PPT_maxVDDCI}mV, TC: ${PPT_maxTC}"
    echo "POWER PL: ${PPT_PL}W OV: -${PPT_minOPL}%/+${PPT_maxOPL}%, TDC GFX: ${PPT_TDCgfx}A, TDC SOC: ${PPT_TDCsoc}A, TEMP Target: ${PPT_FanTT}C"
}

function navi20_get_defaults(){
    echo -e "${CYAN}Default Power Play settings from VBIOS for Navi20${NOCOLOR}"
    readarray -t data < <( python3 /hive/opt/upp2/upp.py -p $savedpp get \
        overdrive_table/max/0 \
        overdrive_table/max/7 \
        smc_pptable/SocketPowerLimitAc/0 \
        smc_pptable/MinVoltageGfx \
        smc_pptable/MaxVoltageGfx \
        smc_pptable/MinVoltageSoc \
        smc_pptable/MaxVoltageSoc \
        smc_pptable/MemVddciVoltage/0 \
        smc_pptable/MemVddciVoltage/3 \
        smc_pptable/MemMvddVoltage/0 \
        smc_pptable/MemMvddVoltage/3 \
        smc_pptable/FreqTableSocclk/1 \
        smc_pptable/TdcLimit/0 \
        smc_pptable/TdcLimit/1 \
        overdrive_table/min/8 \
        overdrive_table/max/8 \
        overdrive_table/max/13 \
        smc_pptable/FanTargetTemperature \
        smc_pptable/FreqTableUclk/3 \
        smc_pptable/FreqTableSocclk/0 \
    )

    PPT_maxCoreClk=$(( data[0] ))
    PPT_maxMemClk=$(( data[1] ))
    PPT_PL=$(( data[2] ))
    PPT_minVDDcore=$(( data[3] / 4 ))
    PPT_maxVDDcore=$(( data[4] / 4 ))
    PPT_minVDDsoc=$(( data[5] / 4 ))
    PPT_maxVDDsoc=$(( data[6] / 4 ))
    PPT_minVDDCI=$(( data[7] / 4 ))
    PPT_maxVDDCI=$(( data[8] / 4 ))
    PPT_minMVDD=$(( data[9] / 4 ))
    PPT_maxMVDD=$(( data[10] / 4 ))
    PPT_maxSocClk=$(( data[11] ))
    PPT_TDCgfx=$(( data[12] ))
    PPT_TDCsoc=$(( data[13] ))
    PPT_minOPL=$(( data[14] ))
    PPT_maxOPL=$(( data[15] ))
    PPT_maxTC=$(( data[16] ))
    PPT_FanTT=$(( data[17] ))
    PPT_defMemClk=$(( data[18] ))
    PPT_minSocClk=$(( data[19] ))

    echo "CORE Clock max: ${PPT_maxCoreClk}MHz, Voltage: ${PPT_minVDDcore}-${PPT_maxVDDcore}mV, SOC Clock: ${PPT_minSocClk}-${PPT_maxSocClk}MHz, Voltage: ${PPT_minVDDsoc}-${PPT_maxVDDsoc}mV"
    echo "MEMORY Clock def/max: ${PPT_defMemClk}/${PPT_maxMemClk} MHz, Voltage: ${PPT_minMVDD}-${PPT_maxMVDD} mV, VDDCI: ${PPT_minVDDCI}-${PPT_maxVDDCI}mV, TC: ${PPT_maxTC}"
    echo "POWER PL: ${PPT_PL}W OV: -${PPT_minOPL}%/+${PPT_maxOPL}%, TDC GFX: ${PPT_TDCgfx}A, TDC SOC: ${PPT_TDCsoc}A, TEMP Target: ${PPT_FanTT}C"
}

function navi_fix_fans(){
    python3 /hive/opt/upp2/upp.py -p /sys/class/drm/card$cardno/device/pp_table set \
        smc_pptable/FanStopTemp=0 smc_pptable/FanStartTemp=10 smc_pptable/FanZeroRpmEnable=0 \
        --write >/dev/null
}

function navi10_pro_fix(){
    local args=""
    if [[ $gpuname =~ "Radeon Pro W5" ]]; then
        for cap in {0..13}; do
            args+="overdrive_table/cap/${cap}=1 "
        done
        python3 /hive/opt/upp2/upp.py -p /sys/class/drm/card${cardno}/device/pp_table set ${args} --write > /dev/null 2>&1
        if [[ $? != 0 ]]; then
            echo -e "${RED}Failed applying Radeon Pro support${NOCOLOR}"
            echo -e "DEBUG: ${YELLOW}$args${NOCOLOR}"
        else
            echo "${CYAN}Applied Radeon Pro support${NOCOLOR}"
        fi
    fi
}

function vega20_pro_fix(){
    local args=""
    if [[ $gpuname =~ "Radeon Pro VII" ]]; then
		cp -rf /hive/sbin/ppt_eta/ppt_vii.bin $savedpp && cat /hive/sbin/ppt_eta/ppt_vii.bin > /sys/class/drm/card${cardno}/device/pp_table

        if [[ $? != 0 ]]; then
            echo -e "${RED}Failed applying Radeon Pro support${NOCOLOR}"
            echo -e "DEBUG: ${YELLOW}$args${NOCOLOR}"
        else
            echo "${CYAN}Applied Radeon Pro support${NOCOLOR}"
        fi
    fi
}

function vega20_oc(){
    vega20_pro_fix
    vega20_get_defaults

    # Apply OC via SysFS API
    # Core Clock
    local cclk=$VEGA_SafeCoreClock
    if [[ -n $CORE_CLOCK && ${CORE_CLOCK[$i]} -gt 0 && ${CORE_CLOCK[$i]} -le $PPT_maxCoreClk ]]; then
        cclk=${CORE_CLOCK[$i]}
    else
        echo -e "${YELLOW}Warning! No core clock is set or out of range (> ${PPT_maxCoreClk}MHz) - using fail safe ${cclk}MHz${NOCOLOR}"
    fi
    
    # Core Voltage
    local vddc=$VEGA_CVDDC_SAFE
    if [[ -n $CORE_VDDC && ${CORE_VDDC[$i]} -gt 0 && ${CORE_VDDC[$i]} -le $PPT_maxVDDcore ]]; then
        vddc=${CORE_VDDC[$i]}
    else
        echo -e "${YELLOW}Warning! No core voltage is set or out of range (> ${PPT_maxVDDcore}mV) - using fail safe ${vddc}mV${NOCOLOR}"
    fi
    
    # Memory Clock
    local mclk=$PPT_defMemClk
    if [[ -n $MEM_CLOCK && ${MEM_CLOCK[$i]} -gt 0 ]]; then
        mclk=${MEM_CLOCK[$i]}
    else
        echo -e "${YELLOW}Warning! No memory clock is set or out of range (> ${PPT_maxMemClk}MHz) - using default ${mclk}MHz${NOCOLOR}"
    fi
    echo -e "${CYAN}Applying OC via SysFS API ${NOCOLOR}"
    set_CoreMemOC "${cclk}" "${mclk}" "${vddc}"
    echo -e "Setting CORE: ${GREEN}${cclk}MHz${NOCOLOR}@${GREEN}${vddc}mV${NOCOLOR} MEM: ${GREEN}${mclk}MHz${NOCOLOR}"
    # EXPERIMENTAL UV
    local args=
    if [[ -n $SOCVDDMAX && ${SOCVDDMAX[$i]} -gt $PPT_minVDDsoc && ${SOCVDDMAX[$i]} -le $PPT_maxVDDsoc ]]; then
        local vddcr_soc=$(echo "scale=3; ${SOCVDDMAX[$i]}/1000" | bc | awk '{printf "%0.3f", $0}' )
        args+="-vddcr_soc=$vddcr_soc "
    fi
    
    if [[ -n $MVDD && ${MVDD[$i]} -gt $PPT_minMVDD && ${MVDD[$i]} -le $PPT_maxMVDD ]]; then
        local vddio_mem=$(echo "scale=3; ${MVDD[$i]}/1000" | bc | awk '{printf "%0.3f", $0}' )
        local vddcr_hbm=$(echo "scale=3; ${MVDD[$i]}/1000" | bc | awk '{printf "%0.3f", $0}' )
        args+="-vddio_mem=$vddio_mem -vddcr_hbm=$vddcr_hbm "
    fi
    
    if [[ -n $VDDCI && ${VDDCI[$i]} -gt $PPT_minVDDCI && ${VDDCI[$i]} -le $PPT_maxVDDCI ]]; then
        local vddci_mem=$(echo "scale=3; ${VDDCI[$i]}/1000" | bc | awk '{printf "%0.3f", $0}' )
        args+="-vddci_mem=$vddci_mem "
    fi
    
    if [[ -n $args ]]; then
        atitool -i="$i" -debug=0 -v=silent "$args" > /dev/null 2>&1 && echo -e "${CYAN}Experimental settings applied${NOCOLOR}" || echo -e "${YELLOW}Experimental settings applied with errors${NOCOLOR}"
    fi
}

function navi10_oc(){
    # Get defaults PowerPlay settings from VBIOS
    navi10_get_defaults
    # Fix Navi Fans
    navi_fix_fans

    # Modify some PPT values
    navi10_pro_fix
    local args=""
    # SoC Clock
    local soc_clk=${PPT_maxSocClk}
    if [[ -n $SOCCLK && ${SOCCLK[$i]} -gt 0 && ${SOCCLK[$i]} -le $PPT_maxSocClk ]]; then
        soc_clk=${SOCCLK[$i]}
    fi
    args+="smc_pptable/FreqTableSocclk/1=${soc_clk} "
    
    # SoC Voltage
    local soc_vdd=$((PPT_maxVDDsoc * 4))
    if [[ -n $SOCVDDMAX && ${SOCVDDMAX[$i]} -gt 0 && ${SOCVDDMAX[$i]} -le $NAVI_SOC_VDD_MAX ]]; then
        if [[ ${SOCVDDMAX[$i]} -lt $NAVI_SOC_VDD_MIN ]]; then
           soc_vdd=$((NAVI_SOC_VDD_MIN * 4))
        else
           soc_vdd=$((${SOCVDDMAX[$i]} * 4 ))
        fi
    fi
    args+="smc_pptable/MaxVoltageSoc=${soc_vdd} "

    # Memory Controller Interface Voltage
    local mem_vddci=$((PPT_maxVDDCI * 4))
    if [[ -n $VDDCI && ${VDDCI[$i]} -gt 0 && ${VDDCI[$i]} -le $NAVI_VDDCI_MAX ]]; then
       if [[ ${VDDCI[$i]} -lt $NAVI_VDDCI_MIN ]]; then
           mem_vddci=$((NAVI_VDDCI_MIN * 4 ))
       else
           mem_vddci=$((${VDDCI[$i]} * 4 ))
       fi
    fi
    args+="smc_pptable/MemVddciVoltage/1=${mem_vddci} smc_pptable/MemVddciVoltage/2=${mem_vddci} smc_pptable/MemVddciVoltage/3=${mem_vddci} "

    # Memory Voltage
    mem_vdd=$((PPT_maxMVDD * 4))
    if [[ -n $MVDD && ${MVDD[$i]} -gt 0 && ${MVDD[$i]} -le $NAVI_MVDD_MAX ]]; then
       if [[ ${MVDD[$i]} -lt $NAVI_MVDD_MIN ]]; then
           mem_vdd=$((NAVI_MVDD_MIN * 4))
       else
           mem_vdd=$((${MVDD[$i]} * 4))
       fi
    fi
    args+="smc_pptable/MemMvddVoltage/1=${mem_vdd} smc_pptable/MemMvddVoltage/2=${mem_vdd} smc_pptable/MemMvddVoltage/3=${mem_vdd} "

    # CORE clock
    if [[ -n $CORE_CLOCK && ${CORE_CLOCK[$i]} -gt $NAVI_MinCoreClock && ${CORE_CLOCK[$i]} -le $PPT_maxCoreClk ]]; then
        cclk=${CORE_CLOCK[$i]}
    else
        cclk=$NAVI_SafeCoreClock
        echo -e "${YELLOW}Warning! No core clock is set - using ${cclk}MHz fail safe clock${NOCOLOR}"
    fi

    # Memory clock
    local mem_clk_max=$PPT_maxMemClk
    local mem_clk=$PPT_defMemClk
    [[ $NAVI_MaxMemClock -lt $PPT_maxMemClk ]] && NAVI_MaxMemClock=$PPT_maxMemClk
    if [[ -n $MEM_CLOCK && ${MEM_CLOCK[$i]} -gt 0 && ${MEM_CLOCK[$i]} -le $NAVI_MaxMemClock ]]; then
        mem_clk=${MEM_CLOCK[$i]}
        [[ $mem_clk -gt $PPT_maxMemClk ]] && mem_clk_max=$mem_clk
    else
        echo -e "${YELLOW}Warning! No memory clock is set or out of range - using ${mem_clk}MHz as fail safe clock${NOCOLOR}"
    fi
    args+="overdrive_table/max/8=${mem_clk_max} "

    # Core voltage
    local vddc=$NAVI_CVDDC_SAFE
    local vddc_min=$PPT_minVDDcore
    if [[ -n $CORE_VDDC && ${CORE_VDDC[$i]} -ge $NAVI_CVDDC_MIN && ${CORE_VDDC[$i]} -le $PPT_maxVDDcore ]]; then
        vddc=${CORE_VDDC[$i]}
        [[ ${CORE_VDDC[$i]} -lt $PPT_minVDDcore ]] && vddc_min=$vddc
    else
        echo -e "${YELLOW}VDDC out of range or not set! Set ${NAVI_CVDDC_SAFE} mV as fail-safe core voltage${NOCOLOR}"
    fi
    args+="overdrive_table/min/3=${vddc_min} overdrive_table/min/5=${vddc_min} overdrive_table/min/7=${vddc_min} smc_pptable/MinVoltageGfx=$((vddc_min*4)) "
    
    python3 /hive/opt/upp2/upp.py -p /sys/class/drm/card${cardno}/device/pp_table set ${args} --write > /dev/null 2>&1
    if [[ $? != 0 ]]; then
        echo -e "${RED}Changes to Power Play table not applied${NOCOLOR}"
        echo -e "DEBUG: ${YELLOW}$args${NOCOLOR}"
    else
        echo "${CYAN}Applying changes to Power Play table ${NOCOLOR}"
        echo -e "SOC: ${GREEN}${soc_clk}MHz${NOCOLOR}@${GREEN}$((soc_vdd/4))mV${NOCOLOR} MCLK max: ${GREEN}${mem_clk_max}MHz${NOCOLOR} VDDC min: ${GREEN}${vddc_min}mV${NOCOLOR} VDDCI: ${GREEN}$((mem_vddci/4))mV${NOCOLOR} MVDD: ${GREEN}$((mem_vdd/4))mV${NOCOLOR}"
    fi

    # Apply OC via SysFS API
    echo -e "${CYAN}Applying OC via SysFS API ${NOCOLOR}"
    set_CoreMemOC "$cclk" "$mem_clk" "$vddc"
    echo -e "Setting CORE: ${GREEN}${cclk}MHz${NOCOLOR}@${GREEN}${vddc}mV${NOCOLOR} MEM: ${GREEN}${mem_clk}MHz${NOCOLOR}"
}

function bc250_oc(){

    # CORE clock
    if [[ -n $CORE_CLOCK && ${CORE_CLOCK[$i]} -gt $NAVI_MinCoreClock ]]; then
        cclk=${CORE_CLOCK[$i]}
    else
        cclk=$NAVI_SafeCoreClock
        echo -e "${YELLOW}Warning! No core clock is set - using ${cclk}MHz fail safe clock${NOCOLOR}"
    fi

    # Core voltage
    local vddc=$NAVI_CVDDC_SAFE
    local vddc_min=$NAVI_CVDDC_MIN
    if [[ -n $CORE_VDDC && ${CORE_VDDC[$i]} -ge $NAVI_CVDDC_MIN && ${CORE_VDDC[$i]} -le $NAVI_CVDDC_MAX  ]]; then
        vddc=${CORE_VDDC[$i]}
        [[ ${CORE_VDDC[$i]} -lt $NAVI_CVDDC_MIN ]] && vddc_min=$vddc
    else
        echo -e "${YELLOW}VDDC out of range or not set! Set ${NAVI_CVDDC_SAFE} mV as fail-safe core voltage${NOCOLOR}"
    fi

    # Apply OC via SysFS API
    echo -e "${CYAN}Applying OC via SysFS API ${NOCOLOR}"
    set_CoreMemOC "$cclk" "$mem_clk" "$vddc"
    echo -e "Setting CORE: ${GREEN}${cclk}MHz${NOCOLOR}@${GREEN}${vddc}mV${NOCOLOR} MEM: ${GREEN}${mem_clk}MHz${NOCOLOR}"
}

function navi20_oc(){
    navi20_get_defaults
    navi_fix_fans

    # Modify some PPT values
    local args=""
    # SoC Clock
    local soc_clk=
    if [[ -n $SOCCLK && ${SOCCLK[$i]} -gt 0 && ${SOCCLK[$i]} -le $PPT_maxSocClk ]]; then
        soc_clk=${SOCCLK[$i]}
    else
        soc_clk=${PPT_maxSocClk}
    fi
    args+="smc_pptable/FreqTableSocclk/1=${soc_clk} "
    local soc_t0=$PPT_minSocClk
    for soc_tmp in 534 601 641 739 801 873
    do
        [[ $soc_tmp -lt $soc_clk ]] && soc_t0=$soc_tmp || break
    done
    args+="smc_pptable/FreqTableSocclk/0=${soc_t0} "
#    args+="smc_pptable/FreqTableSocclk/0=800 "
    
    # SoC Voltage
    local soc_vdd=$((PPT_maxVDDsoc * 4))
    if [[ -n $SOCVDDMAX && ${SOCVDDMAX[$i]} -gt 0 && ${SOCVDDMAX[$i]} -le $NAVI_SOC_VDD_MAX ]]; then
        if [[ ${SOCVDDMAX[$i]} -lt $NAVI_SOC_VDD_MIN ]]; then
            soc_vdd=$((NAVI_SOC_VDD_MIN * 4 ))
        else
            soc_vdd=$((${SOCVDDMAX[$i]} * 4 ))
        fi
        args+="smc_pptable/MaxVoltageSoc=${soc_vdd} "
        args+="smc_pptable/MinVoltageSoc=${soc_vdd} "
        args+="smc_pptable/MinVoltageUlvSoc=$((${soc_vdd} - 100 )) "
    else
        args+="smc_pptable/MaxVoltageSoc=$((PPT_maxVDDsoc * 4)) "
        args+="smc_pptable/MinVoltageSoc=$((PPT_minVDDsoc * 4)) "
        args+="smc_pptable/MinVoltageUlvSoc=$(($PPT_minVDDsoc - 100 )) "
    fi

    # Memory Controller Interface Voltage
    local mem_vddci=$((PPT_maxVDDCI * 4))
    if [[ -n $VDDCI && ${VDDCI[$i]} -gt 0 && ${VDDCI[$i]} -le $NAVI_VDDCI_MAX ]]; then
       if [[ ${VDDCI[$i]} -lt $NAVI_VDDCI_MIN ]]; then
           mem_vddci=$((NAVI_VDDCI_MIN * 4 ))
       else
           mem_vddci=$((${VDDCI[$i]} * 4 ))
       fi
    fi
    args+="smc_pptable/MemVddciVoltage/1=${mem_vddci} smc_pptable/MemVddciVoltage/2=${mem_vddci} smc_pptable/MemVddciVoltage/3=${mem_vddci} "

    # Memory Voltage
    mem_vdd=$((PPT_maxMVDD * 4))
    if [[ -n $MVDD && ${MVDD[$i]} -gt 0 && ${MVDD[$i]} -le $NAVI_MVDD_MAX ]]; then
       if [[ ${MVDD[$i]} -lt $NAVI_MVDD_MIN ]]; then
           mem_vdd=$((NAVI_MVDD_MIN * 4))
       else
           mem_vdd=$((${MVDD[$i]} * 4))
       fi
    fi
    args+="smc_pptable/MemMvddVoltage/1=${mem_vdd} smc_pptable/MemMvddVoltage/2=${mem_vdd} smc_pptable/MemMvddVoltage/3=${mem_vdd} "
    
    # Adjust TDC Limit by +10% for some RX 6800 models with TDC Limit 30A
    local tdc_soc=$PPT_TDCsoc
    if [[ $PPT_TDCsoc -eq 30 && $gpuname =~ "6800" ]]; then
        tdc_soc=$(echo "scale=1; $PPT_TDCsoc*1.1" | bc | awk '{printf "%.0f", $1}')
        args+="smc_pptable/TdcLimit/1=${tdc_soc} "
    fi

    # Fixed Fclk for some RX 6800 models e.g. ASRock
#    if [[ $gpuname =~ "6800" && $(cat /sys/class/drm/card${cardno}/device/revision) == "0xc3" ]]; then
        let fclk=18*$MEM_CLOCK/7-10390/7;
        args+="smc_pptable/FreqTableFclk/0=$fclk "
#    fi

    # CORE clock
    if [[ -n $CORE_CLOCK && ${CORE_CLOCK[$i]} -ge $NAVI_MinCoreClock && ${CORE_CLOCK[$i]} -le $PPT_maxCoreClk ]]; then
        cclk=${CORE_CLOCK[$i]}
    else
        cclk=$NAVI_SafeCoreClock
        echo -e "${YELLOW}Warning! No core clock is set - using ${cclk}MHz fail safe clock${NOCOLOR}"
    fi

    # Memory clock
    local mem_clk=$PPT_defMemClk
    if [[ -n $MEM_CLOCK && ${MEM_CLOCK[$i]} -gt 0 && ${MEM_CLOCK[$i]} -le $PPT_maxMemClk ]]; then
        mem_clk=${MEM_CLOCK[$i]}
		args+="overdrive_table/max/7=1200 "
		args+="smc_pptable/FreqTableUclk/3=${NAVI_MaxMemClock} "

    else
        echo -e "${YELLOW}Warning! No memory clock is set or out of range - using ${mem_clk}MHz as fail safe clock${NOCOLOR}"
    fi

    # Core voltage
    local vddc=$NAVI_CVDDC_SAFE
    if [[ -n $CORE_VDDC && ${CORE_VDDC[$i]} -ge $NAVI_CVDDC_MIN && ${CORE_VDDC[$i]} -le $PPT_maxVDDcore ]]; then
        vddc=${CORE_VDDC[$i]}
    else
        echo -e "${YELLOW}Warning! No core voltage is set - using ${vddc}mV as fail safe voltage${NOCOLOR}"
    fi
    
    #echo $cclk $vddc
    if [[ -n $CORE_CLOCK && ${cclk} -gt $NAVI_MinCoreClock && ${vddc} -gt ${NAVI_CVDDC_MIN} ]]; then
        python3 /hive/opt/upp2/upp.py -p /sys/class/drm/card${cardno}/device/pp_table set_curve_gfx ${cclk} ${vddc} --write > /dev/null 2>&1
        python3 /hive/opt/upp2/upp.py -p /sys/class/drm/card${cardno}/device/pp_table set_curve_gfx ${cclk} ${vddc} --write > /dev/null 2>&1
        [[ $? != 0 ]] && echo -e "${RED}Voltage curve for GFX not applied${NOCOLOR}" #|| echo "${CYAN}Voltage curve for GFX adjusted${NOCOLOR}"
    fi
    
    python3 /hive/opt/upp2/upp.py -p /sys/class/drm/card${cardno}/device/pp_table set ${args} --write > /dev/null 2>&1
    if [[ $? != 0 ]]; then
        echo -e "${RED}Changes to Power Play table not applied${NOCOLOR}"
        echo -e "DEBUG: ${YELLOW}$args${NOCOLOR}"
    else
        echo "${CYAN}Applying changes to Power Play table ${NOCOLOR}"
        echo -e "SOC: ${GREEN}${soc_clk}MHz${NOCOLOR}@${GREEN}$((soc_vdd/4))mV${NOCOLOR} (TDC Limit ${GREEN}${tdc_soc}A${NOCOLOR}) VDDCI: ${GREEN}$((mem_vddci/4))mV${NOCOLOR} MVDD: ${GREEN}$((mem_vdd/4))mV${NOCOLOR}"
    fi

    # Apply OC via SysFS API (voltage set via CurveGFX)
    echo -e "${CYAN}Applying OC via SysFS API ${NOCOLOR}"
    set_CoreMemOC "$cclk" "$mem_clk"
    echo -e "Setting CORE: ${GREEN}${cclk}MHz${NOCOLOR}@${GREEN}${vddc}mV${NOCOLOR} MEM: ${GREEN}${mem_clk}MHz${NOCOLOR}"
}


##################################################
# main
##################################################
if [[ IS_VEGA20 -gt 0 ]]; then
    vega20_oc
elif [[ IS_NAVI10 -gt 0 ]]; then
    navi10_oc
elif [[ IS_BC250 -gt 0 ]]; then
    bc250_oc
elif [[ IS_NAVI20 -gt 0 ]]; then
    navi20_oc
else
    echo -e ${RED}OC not applied due unknown GPU type${NOCOLOR}
fi

set_PowerLimit
set_FanSpeed

echo '0' > /sys/class/drm/card${cardno}/device/pp_dpm_fclk
