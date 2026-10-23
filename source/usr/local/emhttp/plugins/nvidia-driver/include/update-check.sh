#!/bin/bash
KERNEL_V="$(uname -r)"
SET_DRV_V="$(cat /boot/config/plugins/nvidia-driver/settings.cfg | grep "driver_version" | cut -d '=' -f2)"
if [ "${SET_DRV_V}" == "latest_nos" ]; then
  export PACKAGE="nvos"
else
  export PACKAGE="nvidia"
fi
DL_URL="https://github.com/unraid/unraid-nvidia-driver/releases/download/${KERNEL_V}"
INSTALLED_V="$(nvidia-smi | grep NVIDIA-SMI | cut -d ' ' -f3)"

download() {
if wget -q -nc --show-progress --progress=bar:force:noscroll -O "/boot/config/plugins/nvidia-driver/packages/${KERNEL_V%%-*}/${LAT_PACKAGE}" "${DL_URL}/${LAT_PACKAGE}" ; then
  wget -q -nc --show-progress --progress=bar:force:noscroll -O "/boot/config/plugins/nvidia-driver/packages/${KERNEL_V%%-*}/${LAT_PACKAGE}.md5" "${DL_URL}/${LAT_PACKAGE}.md5"
  if [ "$(md5sum /boot/config/plugins/nvidia-driver/packages/${KERNEL_V%%-*}/${LAT_PACKAGE} | awk '{print $1}')" != "$(cat /boot/config/plugins/nvidia-driver/packages/${KERNEL_V%%-*}/${LAT_PACKAGE}.md5 | awk '{print $1}')" ]; then
    echo
    echo "-----错误：操作失败------"
    echo "--------------------------------校验失败！---------------------------------"
    /usr/local/emhttp/plugins/dynamix/scripts/notify -e "Nvidia Driver" -s "Nvidia 驱动" -d "发现 Nvidia 新驱动 v$(echo $LAT_PACKAGE | cut -d '-' -f2)，但校验失败！请尝试手动下载并安装驱动。" -i "alert" -l "/Settings/nvidia-driver"
    crontab -l | grep -v '/usr/local/emhttp/plugins/nvidia-driver/include/update-check.sh'  | crontab -
    rm -rf /boot/config/plugins/nvidia-driver/packages/${KERNEL_V%%-*}/${LAT_PACKAGE}*
    exit 1
  fi
  echo
  echo "-----------已下载 Nvidia 驱动包 v$(echo $LAT_PACKAGE | cut -d '-' -f2)-----------"
  /usr/local/emhttp/plugins/dynamix/scripts/notify -e "Nvidia Driver" -s "Nvidia 驱动" -d "已发现并下载 Nvidia 新驱动 v$(echo $LAT_PACKAGE | cut -d '-' -f2)！请重启服务器以安装新版本。" -l "/Main"
  crontab -l | grep -v '/usr/local/emhttp/plugins/nvidia-driver/include/update-check.sh'  | crontab -
else
  echo
  echo "---------------无法下载 Nvidia 驱动包 v$(echo $LAT_PACKAGE | cut -d '-' -f2)----------------"
  /usr/local/emhttp/plugins/dynamix/scripts/notify -e "Nvidia Driver" -s "Nvidia 驱动" -d "发现 Nvidia 新驱动 v$(echo $LAT_PACKAGE | cut -d '-' -f2)，但下载失败！请尝试手动下载驱动。" -i "alert" -l "/Settings/nvidia-driver"
  crontab -l | grep -v '/usr/local/emhttp/plugins/nvidia-driver/include/update-check.sh'  | crontab -
  exit 1
fi
}

#Check if one of latest, latest_prb or latest_nfb is checked otherwise exit
if [[ "${SET_DRV_V}" != "latest" && "${SET_DRV_V}" != "latest_prb" && "${SET_DRV_V}" != "latest_nfb" ]]; then
  exit 0
elif [ "${SET_DRV_V}" == "latest" ]; then
  LAT_PACKAGE="$(wget -qO- https://api.github.com/repos/unraid/unraid-nvidia-driver/releases/tags/${KERNEL_V} | jq -r '.assets[].name' | grep "$PACKAGE" | grep -E -v '\.md5$' | sort -V | tail -1)"
  if [ -z ${LAT_PACKAGE} ]; then
    logger "Nvidia-Driver-Plugin: 自动更新检查失败，无法获取最新版本号！"
    exit 1
  elif [ "$(echo "$LAT_PACKAGE" | cut -d '-' -f2)" != "${INSTALLED_V}" ]; then
    download
  fi
elif [ "${SET_DRV_V}" == "latest_prb" ]; then
  AVAIL_V="$(wget -qO- https://api.github.com/repos/unraid/unraid-nvidia-driver/releases/tags/${KERNEL_V} | jq -r '.assets[].name' | grep "$PACKAGE" | grep -E -v '\.md5$' | sort -V)"
  PRB_V="$(wget -qO- https://raw.githubusercontent.com/unraid/unraid-nvidia-driver/master/versions.json | jq -r '.branches.production[]' | sort -V)"
  LAT_PRB_V="$(comm -12 <(echo "$(echo "$AVAIL_V" | cut -d '-' -f2 | awk -F '.' '{printf "%d.%03d.%d\n", $1,$2,$3}' | awk -F '.' '{printf "%d.%03d.%02d\n", $1,$2,$3}')") <(echo "${PRB_V}" | awk -F '.' '{printf "%d.%03d.%d\n", $1,$2,$3}' | awk -F '.' '{printf "%d.%03d.%02d\n", $1,$2,$3}') | tail -1 | awk -F '.' '{printf "%d.%02d.%02d\n", $1,$2,$3}' | awk '{sub(/\.0+$/,"")}1')"
  LAT_PACKAGE="$(echo "${AVAIL_V}" | grep "\-${LAT_PRB_V}-")"
  if [ -z ${LAT_PACKAGE} ]; then
    logger "Nvidia-Driver-Plugin: 自动更新检查失败，无法获取最新生产分支版本号！"
    exit 1
  elif [ "$(echo "$LAT_PACKAGE" | cut -d '-' -f2)" != "${INSTALLED_V}" ]; then
    download
  fi
elif [ "${SET_DRV_V}" == "latest_nfb" ]; then
  AVAIL_V="$(wget -qO- https://api.github.com/repos/unraid/unraid-nvidia-driver/releases/tags/${KERNEL_V} | jq -r '.assets[].name' | grep "$PACKAGE" | grep -E -v '\.md5$' | sort -V)"
  NFB_V="$(wget -qO- https://raw.githubusercontent.com/unraid/unraid-nvidia-driver/master/versions.json | jq -r '.branches.newfeature[]' | sort -V)"
  LAT_NFB_V="$(comm -12 <(echo "$(echo "$AVAIL_V" | cut -d '-' -f2 | awk -F '.' '{printf "%d.%03d.%d\n", $1,$2,$3}' | awk -F '.' '{printf "%d.%03d.%02d\n", $1,$2,$3}')") <(echo "${NFB_V}" | awk -F '.' '{printf "%d.%03d.%d\n", $1,$2,$3}' | awk -F '.' '{printf "%d.%03d.%02d\n", $1,$2,$3}') | tail -1 | awk -F '.' '{printf "%d.%02d.%02d\n", $1,$2,$3}' | awk '{sub(/\.0+$/,"")}1')"
  LAT_PACKAGE="$(echo "${AVAIL_V}" | grep "\-${LAT_NFB_V}-")"
  if [ -z ${LAT_PACKAGE} ]; then
    logger "Nvidia-Driver-Plugin: 自动更新检查失败，无法获取最新新功能分支版本号！"
    exit 1
  elif [ "$(echo "$LAT_PACKAGE" | cut -d '-' -f2)" != "${INSTALLED_V}" ]; then
    download
  fi
elif [ "${SET_DRV_V}" == "latest_nos" ]; then
  LAT_PACKAGE="$(wget -qO- https://api.github.com/repos/unraid/unraid-nvidia-driver/releases/tags/${KERNEL_V} | jq -r '.assets[].name' | grep -E -v '\.md5$' | grep "${PACKAGE}" | sort -V | tail -1)"
  if [ -z ${LAT_PACKAGE} ]; then
    logger "Nvidia-Driver-Plugin: 自动更新检查失败，无法获取最新开源内核驱动版本号！"
    exit 1
  elif [ "$(echo "$LAT_PACKAGE" | cut -d '-' -f2 )" != "${INSTALLED_V}" ]; then
    download
  fi
fi

#Check for old packages that are not suitable for this Kernel and not suitable for the current Nvidia driver version
rm -rf $(ls -d /boot/config/plugins/nvidia-driver/packages/* 2>/dev/null | grep -v "${KERNEL_V%%-*}")
rm -f $(ls /boot/config/plugins/nvidia-driver/packages/${KERNEL_V%%-*}/* 2>/dev/null | grep -v "$LAT_PACKAGE")
