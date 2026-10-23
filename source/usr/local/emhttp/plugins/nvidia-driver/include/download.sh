#!/bin/bash

# Check GitHub API call rate limit
RATE_LIMIT="$(wget -qO- -T 10 https://api.github.com/rate_limit | jq -r '.rate')"
if [ "$(echo "${RATE_LIMIT}" | jq -r '.remaining')" == "0" ]; then
  RESET="$(date -d @"$(echo "${RATE_LIMIT}" | jq -r '.reset')" "+%Y-%m-%d %H:%M:%S")"
  echo "-----错误：操作失败------"
  echo "当前 IP 的 GitHub API 请求次数已用尽。"
  echo "请求额度恢复时间： <b>${RESET}</b>"
  exit 1
fi

# Define Variables
export KERNEL_V="$(uname -r)"
export SET_DRV_V="$(grep "driver_version" "/boot/config/plugins/nvidia-driver/settings.cfg" | cut -d '=' -f2)"
if [ "${SET_DRV_V}" == "latest_nos" ]; then
  export PACKAGE="nvos"
  export OS="开源内核"
  LAT_NOS_AVAIL="$(wget -qO- https://api.github.com/repos/unraid/unraid-nvidia-driver/releases/tags/${KERNEL_V} | jq -r '.assets[].name' | grep -E -v '\.md5$' | grep "${PACKAGE}" | awk -F "-" '{print $2}' | sort -V | tail -1)"
else
  export PACKAGE="nvidia"
  export DRIVER_AVAIL="$(wget -qO- https://api.github.com/repos/unraid/unraid-nvidia-driver/releases/tags/${KERNEL_V} | jq -r '.assets[].name' | grep -E ${PACKAGE} | grep -E -v '\.md5$' | sort -V)"
  export BRANCHES="$(wget -qO- https://raw.githubusercontent.com/unraid/unraid-nvidia-driver/master/versions.json | jq -r '.branches')"
fi
export DL_URL="https://github.com/unraid/unraid-nvidia-driver/releases/download/${KERNEL_V}"
export CUR_V="$(nvidia-smi | grep NVIDIA-SMI | cut -d ' ' -f3)"

#Download Nvidia Driver Package
download() {
if wget -q -nc --show-progress --progress=bar:force:noscroll -O "/boot/config/plugins/nvidia-driver/packages/${KERNEL_V%%-*}/${LAT_PACKAGE}" "${DL_URL}/${LAT_PACKAGE}" ; then
  wget -q -nc --show-progress --progress=bar:force:noscroll -O "/boot/config/plugins/nvidia-driver/packages/${KERNEL_V%%-*}/${LAT_PACKAGE}.md5" "${DL_URL}/${LAT_PACKAGE}.md5"
  if [ "$(md5sum /boot/config/plugins/nvidia-driver/packages/${KERNEL_V%%-*}/${LAT_PACKAGE} | awk '{print $1}')" != "$(cat /boot/config/plugins/nvidia-driver/packages/${KERNEL_V%%-*}/${LAT_PACKAGE}.md5 | awk '{print $1}')" ]; then
    echo
    echo "-----错误：操作失败------"
    echo "--------------------------------校验失败！---------------------------------"
    rm -rf /boot/config/plugins/nvidia-driver/packages/${KERNEL_V%%-*}/${LAT_PACKAGE}*
    exit 1
  fi
  echo
  echo "-----------已下载 Nvidia 驱动包 v$(echo $LAT_PACKAGE | cut -d '-' -f2)-----------"
else
  echo
  echo "---------------无法下载 Nvidia 驱动包 v$(echo $LAT_PACKAGE | cut -d '-' -f2)----------------"
  exit 1
fi
}

#Check if driver is already downloaded
check() {
if ! ls -1 /boot/config/plugins/nvidia-driver/packages/${KERNEL_V%%-*}/ | grep -q "${PACKAGE}-$(echo $LAT_PACKAGE | cut -d '-' -f2)" ; then
  echo
  echo "+=============================================================================="
  echo "| 注意：请等待操作完成"
  echo "|"
  echo "| 请等待“完成（DONE）”按钮出现，再关闭窗口；下载过程中请勿点击右上角的红色 X！"
  echo "|"
  echo "| 注意：请等待操作完成"
  echo "+=============================================================================="
  echo
  echo "----------------正在下载 Nvidia ${OS}驱动包 v$(echo $LAT_PACKAGE | cut -d '-' -f2)-----------------"
  echo "---------下载可能需要一些时间，请勿关闭此窗口！------------"
  download
else
  echo
  echo "--------Nvidia ${OS}驱动 v$(echo $LAT_PACKAGE | cut -d '-' -f2) 已下载，无需重复下载！---------"
  echo
  echo "------------------------------正在校验驱动包……------------------------------"
  if [ "$(md5sum /boot/config/plugins/nvidia-driver/packages/${KERNEL_V%%-*}/${LAT_PACKAGE} | awk '{print $1}')" != "$(cat /boot/config/plugins/nvidia-driver/packages/${KERNEL_V%%-*}/${LAT_PACKAGE}.md5 | awk '{print $1}')" ]; then
    rm -rf /boot/config/plugins/nvidia-driver/packages/${KERNEL_V%%-*}/${LAT_PACKAGE}*
    echo
    echo "-----错误：操作失败-----"
    echo "--------------------------------校验失败！--------------------------------"
    echo
    echo "---------------正在重新下载 Nvidia ${OS}驱动 v$(echo $LAT_PACKAGE | cut -d '-' -f2)-------------"
    echo
    echo "+=============================================================================="
    echo "| 注意：请等待操作完成"
    echo "|"
    echo "| 请等待“完成（DONE）”按钮出现，再关闭窗口；下载过程中请勿点击右上角的红色 X！"
    echo "|"
    echo "| 注意：请等待操作完成"
    echo "+=============================================================================="
    download
  else
    echo
    echo "----------------------------------校验通过！---------------------------------"
    exit 0
  fi
fi
}

if [ ! -d "/boot/config/plugins/nvidia-driver/packages/${KERNEL_V%%-*}" ]; then
  mkdir -p "/boot/config/plugins/nvidia-driver/packages/${KERNEL_V%%-*}"
fi

if [ "${SET_DRV_V}" == "latest" ]; then
  export LAT_PACKAGE="$(echo "$DRIVER_AVAIL" | tail -1)"
  if [ -z "$LAT_PACKAGE" ]; then
    if [ -z "${CUR_V}" ]; then
      echo
      echo "-----错误：操作失败------"
      echo "---无法获取最新的 Nvidia 驱动版本，且未检测到已安装的本地驱动---"
      echo "-----请等待一小时后重试；如果仍然失败，-----"
      echo "------请在中文版仓库的 Issues 中反馈，并附上错误信息。------"
      exit 1
    else
      LAT_PACKAGE=$PACKAGE-$CUR_V-$KERNEL_V-1.txz
    fi
  fi
elif [ "${SET_DRV_V}" == "latest_prb" ]; then
  LAT_PRB_AVAIL="$(echo "$BRANCHES" | jq -r '.production[]' | sort -V)"
  if [ -z "$LAT_PRB_AVAIL" ]; then
    if [ -z "${CUR_V}" ]; then
      echo
      echo "-----错误：操作失败------"
      echo "----无法获取生产分支版本，且未检测到已安装的本地驱动-----"
      echo "-----请等待一小时后重试；如果仍然失败，-----"
      echo "------请在中文版仓库的 Issues 中反馈，并附上错误信息。------"
      exit 1
    else
      LAT_PACKAGE=$PACKAGE-$CUR_V-$KERNEL_V-1.txz
    fi
  elif [ -z "$DRIVER_AVAIL" ]; then
    if [ -z "${CUR_V}" ]; then
      echo
      echo "-----错误：操作失败------"
      echo "------无法获取 Nvidia 驱动版本，且未检测到已安装的本地驱动------"
      echo "-----请等待一小时后重试；如果仍然失败，-----"
      echo "------请在中文版仓库的 Issues 中反馈，并附上错误信息。------"
      exit 1
    else
      LAT_PACKAGE=$PACKAGE-$CUR_V-$KERNEL_V-1.txz
    fi
  else
    LAT_PRB_V="$(comm -12 <(echo "$DRIVER_AVAIL" | cut -d '-' -f2 | awk -F '.' '{printf "%d.%03d.%d\n", $1,$2,$3}' | awk -F '.' '{printf "%d.%03d.%02d\n", $1,$2,$3}') <(echo "$LAT_PRB_AVAIL" | awk -F '.' '{printf "%d.%03d.%d\n", $1,$2,$3}' | awk -F '.' '{printf "%d.%03d.%02d\n", $1,$2,$3}') | sort -V | tail -1 | awk -F '.' '{printf "%d.%02d.%02d\n", $1,$2,$3}' | awk '{sub(/\.0+$/,"")}1')"
    if [ -z "${LAT_PRB_V}" ]; then
      if [ -z "${CUR_V}" ]; then
        echo
        echo "-----错误：操作失败------"
        echo "---无法获取最新的 Nvidia 驱动版本，且未检测到已安装的本地驱动---"
        echo "-----请等待一小时后重试；如果仍然失败，-----"
        echo "------请在中文版仓库的 Issues 中反馈，并附上错误信息。------"
        exit 1
      else
        LAT_PACKAGE="$(echo "$DRIVER_AVAIL" | tail -1)"
        echo "---内核 v${KERNEL_V%%-*} 暂无对应的最新生产分支驱动，将改用最新版 Nvidia 驱动 v$(echo $LAT_PACKAGE | cut -d '-' -f2)---"
        sed -i '/driver_version=/c\driver_version=latest' "/boot/config/plugins/nvidia-driver/settings.cfg"
      fi
    else
      LAT_PACKAGE="$(echo "$DRIVER_AVAIL" | grep "$LAT_PRB_V")"
    fi
  fi
elif [ "${SET_DRV_V}" == "latest_nfb" ]; then
  LAT_NFB_AVAIL="$(echo "$BRANCHES" | jq -r '.newfeature[]' | sort -V)"
  if [ -z "$LAT_NFB_AVAIL" ]; then
    if [ -z "${CUR_V}" ]; then
      echo
      echo "-----错误：操作失败------"
      echo "----无法获取新功能分支版本，且未检测到已安装的本地驱动----"
      echo "-----请等待一小时后重试；如果仍然失败，-----"
      echo "------请在中文版仓库的 Issues 中反馈，并附上错误信息。------"
      exit 1
    else
      LAT_PACKAGE=$PACKAGE-$CUR_V-$KERNEL_V-1.txz
    fi
  elif [ -z "$DRIVER_AVAIL" ]; then
    if [ -z "${CUR_V}" ]; then
      echo
      echo "-----错误：操作失败------"
      echo "------无法获取 Nvidia 驱动版本，且未检测到已安装的本地驱动------"
      echo "-----请等待一小时后重试；如果仍然失败，-----"
      echo "------请在中文版仓库的 Issues 中反馈，并附上错误信息。------"
      exit 1
    else
      LAT_PACKAGE=$PACKAGE-$CUR_V-$KERNEL_V-1.txz
    fi
  else
    LAT_NFB_V="$(comm -12 <(echo "$DRIVER_AVAIL" | cut -d '-' -f2 | awk -F '.' '{printf "%d.%03d.%d\n", $1,$2,$3}' | awk -F '.' '{printf "%d.%03d.%02d\n", $1,$2,$3}') <(echo "$LAT_NFB_AVAIL" | awk -F '.' '{printf "%d.%03d.%d\n", $1,$2,$3}' | awk -F '.' '{printf "%d.%03d.%02d\n", $1,$2,$3}') | sort -V | tail -1 | awk -F '.' '{printf "%d.%02d.%02d\n", $1,$2,$3}' | awk '{sub(/\.0+$/,"")}1')"
    if [ -z "${LAT_NFB_V}" ]; then
      if [ -z "${CUR_V}" ]; then
        echo
        echo "-----错误：操作失败------"
        echo "------无法获取 Nvidia 驱动版本，且未检测到已安装的本地驱动------"
        echo "-----请等待一小时后重试；如果仍然失败，-----"
        echo "------请在中文版仓库的 Issues 中反馈，并附上错误信息。------"
        exit 1
      else
        LAT_PACKAGE="$(echo "$DRIVER_AVAIL" | tail -1)"
        echo "---内核 v${KERNEL_V%%-*} 暂无对应的最新新功能分支驱动，将改用最新版 Nvidia 驱动 v$(echo $LAT_PACKAGE | cut -d '-' -f2)---"
        sed -i '/driver_version=/c\driver_version=latest' "/boot/config/plugins/nvidia-driver/settings.cfg"
      fi
    else
      LAT_PACKAGE="$(echo "$DRIVER_AVAIL" | grep "$LAT_NFB_V")"
    fi
  fi
elif [ "${SET_DRV_V}" == "latest_nos" ]; then
  if [ -z "$LAT_NOS_AVAIL" ]; then
    if [ -z "${CUR_V}" ]; then
      echo
      echo "-----错误：操作失败------"
      echo "----无法获取开源内核驱动版本，且未检测到已安装的本地驱动----"
      echo "-----请等待一小时后重试；如果仍然失败，-----"
      echo "------请在中文版仓库的 Issues 中反馈，并附上错误信息。------"
      exit 1
    else
      export PACKAGE="nvidia"
      LAT_PACKAGE=$PACKAGE-$CUR_V-$KERNEL_V-1.txz
    fi
  else
    LAT_PACKAGE=$PACKAGE-$LAT_NOS_AVAIL-$KERNEL_V-1.txz
  fi
else
  if [ -z "$DRIVER_AVAIL" ]; then
    if [ -z "${CUR_V}" ]; then
      echo
      echo "-----错误：操作失败------"
      echo "---无法获取最新的 Nvidia 驱动版本，且未检测到已安装的本地驱动---"
      echo "-----请等待一小时后重试；如果仍然失败，-----"
      echo "------请在中文版仓库的 Issues 中反馈，并附上错误信息。------"
      exit 1
    else
      LAT_PACKAGE=$PACKAGE-$CUR_V-$KERNEL_V-1.txz
    fi
  else
    LAT_PACKAGE="$(echo "$DRIVER_AVAIL" | grep "$SET_DRV_V")"
    if [ -z "${LAT_PACKAGE}" ]; then
      export LAT_PACKAGE="$(echo "$DRIVER_AVAIL" | tail -1)"
      echo
      echo "---内核 v${KERNEL_V%%-*} 暂无对应的 Nvidia 驱动 v${SET_DRV_V}，将改用最新版 v$(echo $LAT_PACKAGE | cut -d '-' -f2)---"
      sed -i '/driver_version=/c\driver_version=latest' "/boot/config/plugins/nvidia-driver/settings.cfg"
    fi
  fi
fi

#Begin Check
check

#Check for old packages that are not suitable for this Kernel and not suitable for the current Nvidia driver version
rm -rf $(ls -d /boot/config/plugins/nvidia-driver/packages/* 2>/dev/null | grep -v "${KERNEL_V%%-*}")
rm -f $(ls /boot/config/plugins/nvidia-driver/packages/${KERNEL_V%%-*}/* 2>/dev/null | grep -v "$LAT_PACKAGE")

#Display message to reboot server both in Plugin and WebUI
echo
echo "----请重启服务器以安装 Nvidia 新驱动 v$(echo $LAT_PACKAGE | cut -d '-' -f2)！----"
/usr/local/emhttp/plugins/dynamix/scripts/notify -e "Nvidia Driver" -s "Nvidia 驱动" -d "请重启服务器以安装 Nvidia 新驱动 v$(echo $LAT_PACKAGE | cut -d '-' -f2)！" -i "alert" -l "/Main"
