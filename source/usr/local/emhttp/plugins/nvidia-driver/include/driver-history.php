<?php
// Release discovery and package selection are shared by the WebUI and boot installer.
function nvidia_history_parse_name($name, $kernel) {
  if (!preg_match('/^(nvidia|nvos)-(\d{3}\.\d+(?:\.\d+)?)-' . preg_quote($kernel, '/') . '-(\d+)\.txz$/D', $name, $match)) {
    return null;
  }
  return array('name' => $name, 'type' => $match[1], 'version' => $match[2], 'kernel' => $kernel, 'revision' => (int)$match[3]);
}

function nvidia_history_sort($a, $b) {
  $version = version_compare($b['version'], $a['version']);
  return $version ?: (strcmp($a['type'], $b['type']) ?: ($b['revision'] - $a['revision']));
}

function nvidia_history_assets($assets, $kernel) {
  $by_name = array_column($assets, null, 'name');
  $rows = array();
  foreach ($assets as $asset) {
    $row = nvidia_history_parse_name($asset['name'], $kernel);
    if ($row === null || !isset($by_name[$asset['name'] . '.md5'])) continue;
    $row['url'] = $asset['browser_download_url'];
    $row['checksum_url'] = $by_name[$asset['name'] . '.md5']['browser_download_url'];
    $row['size'] = $asset['size'];
    $rows[] = $row;
  }
  usort($rows, 'nvidia_history_sort');
  return $rows;
}

function nvidia_history_json($url) {
  $context = stream_context_create(array('http' => array(
    'timeout' => 15,
    'ignore_errors' => true,
    'header' => "User-Agent: unraid-nvidia-driver\r\nAccept: application/vnd.github+json\r\n"
  )));
  $body = @file_get_contents($url, false, $context);
  $status = isset($http_response_header[0]) ? $http_response_header[0] : '';
  if ($body === false || !preg_match('/\s200\s/', $status)) {
    $data = json_decode((string)$body, true);
    throw new RuntimeException('无法获取驱动列表：' . ($data['message'] ?? ($status ?: '网络连接失败')));
  }
  $data = json_decode($body, true);
  if (!is_array($data)) throw new RuntimeException('驱动列表返回了无效数据。');
  return $data;
}

function nvidia_history_list($kernel, $refresh = false) {
  $cache = '/tmp/nvidia-driver-release-' . $kernel . '.json';
  $stored = is_file($cache) ? json_decode(file_get_contents($cache), true) : null;
  if (!$refresh && isset($stored['rows'], $stored['fetched_at']) && time() - $stored['fetched_at'] < 300) return $stored;
  try {
    $api = 'https://api.github.com/repos/unraid/unraid-nvidia-driver/releases';
    $release = nvidia_history_json($api . '/tags/' . rawurlencode($kernel));
    $assets = array();
    $page = 1;
    do {
      $batch = nvidia_history_json($api . '/' . $release['id'] . '/assets?per_page=100&page=' . $page++);
      $assets = array_merge($assets, $batch);
    } while (count($batch) === 100);
    $result = array('rows' => nvidia_history_assets($assets, $kernel), 'fetched_at' => time());
    file_put_contents($cache, json_encode($result));
    return $result;
  } catch (RuntimeException $error) {
    if (!isset($stored['rows'])) throw $error;
    $stored['notice'] = $error->getMessage() . ' 正在显示上次获取的列表。';
    return $stored;
  }
}

function nvidia_history_settings() {
  return parse_ini_file('/boot/config/plugins/nvidia-driver/settings.cfg', false, INI_SCANNER_RAW);
}

function nvidia_history_save($values) {
  $path = '/boot/config/plugins/nvidia-driver/settings.cfg';
  $text = file_get_contents($path);
  foreach ($values as $key => $value) {
    $line = $key . '=' . $value;
    $pattern = '/^' . preg_quote($key, '/') . '=.*$/m';
    $text = preg_match($pattern, $text) ? preg_replace($pattern, $line, $text) : rtrim($text) . "\n" . $line . "\n";
  }
  if (file_put_contents($path . '.tmp', $text) === false || !rename($path . '.tmp', $path)) {
    throw new RuntimeException('无法保存驱动设置。');
  }
}

function nvidia_history_directory($kernel) {
  return '/boot/config/plugins/nvidia-driver/packages/' . explode('-', $kernel)[0];
}

function nvidia_history_path($kernel, $name) {
  $directory = nvidia_history_directory($kernel);
  return is_file($directory . '/cache/' . $name) ? $directory . '/cache/' . $name : $directory . '/' . $name;
}

// rc.modules installs every matching archive at maxdepth 1 before this plugin runs.
// Keep only the selected archive there; backups belong in the unscanned subdirectory.
function nvidia_history_activate($row) {
  $directory = nvidia_history_directory($row['kernel']);
  $source = nvidia_history_path($row['kernel'], $row['name']);
  if (!is_dir($directory . '/cache')) mkdir($directory . '/cache', 0755, true);
  foreach (glob($directory . '/*.txz') as $path) {
    if (basename($path) === $row['name'] || nvidia_history_parse_name(basename($path), $row['kernel']) === null) continue;
    foreach (array('', '.md5') as $suffix) {
      if (is_file($path . $suffix) && !rename($path . $suffix, $directory . '/cache/' . basename($path) . $suffix)) {
        throw new RuntimeException('无法移动旧驱动缓存，请检查启动盘。');
      }
    }
  }
  if ($source !== $directory . '/' . $row['name']) {
    foreach (array('', '.md5') as $suffix) {
      if (!rename($source . $suffix, $directory . '/' . $row['name'] . $suffix)) throw new RuntimeException('无法切换启动驱动包。');
    }
  }
}

function nvidia_history_verified($path) {
  if (!is_file($path) || !is_file($path . '.md5')) return false;
  $expected = preg_split('/\s+/', trim(file_get_contents($path . '.md5')))[0];
  return preg_match('/^[0-9a-f]{32}$/i', $expected) && strtolower($expected) === md5_file($path);
}

function nvidia_history_choose($rows, $selector, $type = 'nvidia') {
  if (preg_match('/^(latest|latest_prb|latest_nfb|latest_nos)$/D', $selector)) {
    $type = $selector === 'latest_nos' ? 'nvos' : 'nvidia';
    $branch_versions = null;
    if ($selector === 'latest_prb' || $selector === 'latest_nfb') {
      $branch = $selector === 'latest_prb' ? 'production' : 'newfeature';
      $metadata = nvidia_history_json('https://raw.githubusercontent.com/unraid/unraid-nvidia-driver/master/versions.json');
      $branch_versions = array_values($metadata['branches'][$branch]);
    }
    foreach ($rows as $row) {
      if ($row['type'] === $type && ($branch_versions === null || in_array($row['version'], $branch_versions, true))) return $row;
    }
  } else {
    foreach ($rows as $row) {
      if ($row['name'] === $selector || ($row['version'] === $selector && $row['type'] === $type)) return $row;
    }
  }
  throw new RuntimeException('当前内核没有所选版本及模块类型的驱动包。请刷新列表或重新选择，不会自动替换为最新版。');
}

function nvidia_history_download($row) {
  $directory = nvidia_history_directory($row['kernel']) . '/cache';
  if (!is_dir($directory)) mkdir($directory, 0755, true);
  $path = $directory . '/' . $row['name'];
  if (nvidia_history_verified(nvidia_history_path($row['kernel'], $row['name']))) {
    fwrite(STDERR, "已找到并校验本地驱动包：" . $row['name'] . "\n");
    return;
  }
  fwrite(STDERR, "正在下载 " . $row['name'] . "，请等待操作完成后再关闭窗口。\n");
  try {
    foreach (array('.md5' => $row['checksum_url'], '' => $row['url']) as $suffix => $url) {
      passthru('wget -T 30 --tries=2 --show-progress -O ' . escapeshellarg($path . $suffix . '.part') . ' ' . escapeshellarg($url) . ' 1>&2', $status);
      if ($status !== 0) throw new RuntimeException('驱动包或校验文件下载失败，原有设置保持不变。');
    }
    $expected = preg_split('/\s+/', trim(file_get_contents($path . '.md5.part')))[0];
    if (!preg_match('/^[0-9a-f]{32}$/i', $expected) || strtolower($expected) !== md5_file($path . '.part')) {
      throw new RuntimeException('驱动包校验失败，原有设置保持不变。');
    }
    if (!rename($path . '.part', $path) || !rename($path . '.md5.part', $path . '.md5')) {
      throw new RuntimeException('无法保存下载的驱动包。');
    }
  } finally {
    foreach (array('.part', '.md5.part') as $suffix) if (is_file($path . $suffix)) unlink($path . $suffix);
  }
}

function nvidia_history_stage($row, $selector) {
  nvidia_history_activate($row);
  $values = array(
    'driver_version' => $selector,
    'driver_type' => $row['type'],
    'driver_package' => $row['name'],
    'driver_kernel' => $row['kernel']
  );
  if (!in_array($selector, array('latest', 'latest_prb', 'latest_nfb'), true)) $values['update_check'] = 'false';
  nvidia_history_save($values);
}

function nvidia_history_installed() {
  // NVML can fail during a mixed installation; the loaded module remains authoritative.
  $version = is_file('/sys/module/nvidia/version') ? trim(file_get_contents('/sys/module/nvidia/version')) : '';
  $description = is_file('/proc/driver/nvidia/version') ? file_get_contents('/proc/driver/nvidia/version') : '';
  return array('version' => $version, 'type' => strpos($description, 'Open Kernel Module') !== false ? 'nvos' : 'nvidia');
}

function nvidia_history_prune($kernel, $keep_name) {
  $installed = nvidia_history_installed();
  foreach (array_merge(glob(nvidia_history_directory($kernel) . '/*.txz'), glob(nvidia_history_directory($kernel) . '/cache/*.txz')) as $path) {
    $row = nvidia_history_parse_name(basename($path), $kernel);
    if ($row === null || $row['name'] === $keep_name || ($row['version'] === $installed['version'] && $row['type'] === $installed['type'])) continue;
    unlink($path);
    if (is_file($path . '.md5')) unlink($path . '.md5');
  }
}

function nvidia_history_boot($settings, $kernel) {
  $selector = $settings['driver_version'];
  $fixed = !in_array($selector, array('latest', 'latest_prb', 'latest_nfb', 'latest_nos'), true);
  $type = $fixed ? ($settings['driver_type'] ?? 'nvidia') : ($selector === 'latest_nos' ? 'nvos' : 'nvidia');
  $saved = nvidia_history_parse_name($settings['driver_package'] ?? '', $kernel);
  if ($saved !== null && $saved['type'] === $type && (!$fixed || $saved['version'] === $selector) && nvidia_history_verified(nvidia_history_path($kernel, $saved['name']))) return $saved;
  // Existing installations may have a verified local package but no saved filename yet.
  if (empty($settings['driver_package'])) {
    $local = array();
    foreach (array_merge(glob(nvidia_history_directory($kernel) . '/*.txz'), glob(nvidia_history_directory($kernel) . '/cache/*.txz')) as $path) {
      $row = nvidia_history_parse_name(basename($path), $kernel);
      if ($row !== null && $row['type'] === $type && (!$fixed || $row['version'] === $selector)) $local[] = $row;
    }
    usort($local, 'nvidia_history_sort');
    foreach ($local as $row) if (nvidia_history_verified(nvidia_history_path($kernel, $row['name']))) return $row;
  }
  $list = nvidia_history_list($kernel);
  $row = nvidia_history_choose($list['rows'], $selector, $type);
  nvidia_history_download($row);
  return $row;
}

if (realpath($_SERVER['SCRIPT_FILENAME']) === __FILE__) {
  $kernel = trim((string)shell_exec('uname -r'));
  try {
    $settings = nvidia_history_settings();
    if (PHP_SAPI !== 'cli') {
      header('Content-Type: application/json; charset=utf-8');
      $result = nvidia_history_list($kernel, isset($_GET['refresh']));
      $installed = nvidia_history_installed();
      foreach ($result['rows'] as &$row) {
        $row['installed'] = $row['version'] === $installed['version'] && $row['type'] === $installed['type'];
        $row['selected'] = $row['name'] === ($settings['driver_package'] ?? '');
        $row['cached'] = is_file(nvidia_history_path($kernel, $row['name']));
      }
      unset($row);
      echo json_encode(array_merge($result, array('ok' => true, 'kernel' => $kernel, 'selection' => $settings['driver_version'])), JSON_UNESCAPED_UNICODE);
    } elseif ($argv[1] === 'boot') {
      $row = nvidia_history_boot($settings, $kernel);
      nvidia_history_stage($row, $settings['driver_version']);
      echo $row['name'];
    } elseif ($argv[1] === 'prune') {
      nvidia_history_prune($kernel, $argv[2]);
    } elseif ($argv[1] === 'stage') {
      $row = nvidia_history_parse_name($argv[2], $kernel);
      if ($row === null || !nvidia_history_verified(nvidia_history_path($kernel, $row['name']))) throw new RuntimeException('待安装驱动包不存在或校验失败。');
      nvidia_history_stage($row, $settings['driver_version']);
    } elseif ($argv[1] === 'download') {
      $selector = $argv[2];
      echo "正在读取当前内核的驱动列表，请稍候……\n";
      $list = nvidia_history_list($kernel);
      $row = nvidia_history_choose($list['rows'], $selector);
      nvidia_history_download($row);
      $fixed = !in_array($selector, array('latest', 'latest_prb', 'latest_nfb', 'latest_nos'), true);
      nvidia_history_stage($row, $fixed ? $row['version'] : $selector);
      if ($fixed || $selector === 'latest_nos') {
        shell_exec('/usr/local/emhttp/plugins/nvidia-driver/include/exec.sh change_update_check false');
      }
      nvidia_history_prune($kernel, $row['name']);
      echo "驱动包已下载并校验成功，已设为启动版本。请重启服务器以生效。\n";
      shell_exec('/usr/local/emhttp/plugins/dynamix/scripts/notify -e "Nvidia Driver" -s "Nvidia 驱动" -d ' . escapeshellarg('驱动 ' . $row['version'] . ' 已准备就绪，请重启服务器以安装。') . ' -i alert -l /Settings/nvidia-driver');
    }
  } catch (RuntimeException $error) {
    if (PHP_SAPI === 'cli') {
      fwrite(STDERR, $error->getMessage() . "\n");
      exit(1);
    }
    header('Content-Type: application/json; charset=utf-8');
    http_response_code(502);
    echo json_encode(array('ok' => false, 'error' => $error->getMessage()), JSON_UNESCAPED_UNICODE);
  }
}
