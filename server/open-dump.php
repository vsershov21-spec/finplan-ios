<?php
// Расшифровать выгрузку данных: php open-dump.php key.pem dump.bin out.tgz
[$_, $keyf, $in, $out] = $argv;
$raw = file_get_contents($in); $nl = strpos($raw, "\n");
$h = json_decode(substr($raw, 0, $nl), true); $ct = substr($raw, $nl + 1);
if (!is_array($h) || empty($h['ek'])) { fwrite(STDERR, "не похоже на выгрузку Финплана\n"); exit(1); }
$key = openssl_pkey_get_private(file_get_contents($keyf));
if (!openssl_private_decrypt(base64_decode($h['ek']), $k, $key, OPENSSL_PKCS1_OAEP_PADDING)) { fwrite(STDERR, "ключ не подходит: выгрузка сделана для другого сервера\n"); exit(1); }
$plain = openssl_decrypt($ct, 'aes-256-gcm', $k, OPENSSL_RAW_DATA, base64_decode($h['iv']), base64_decode($h['tag']));
if ($plain === false) { fwrite(STDERR, "выгрузка повреждена\n"); exit(1); }
file_put_contents($out, $plain); echo "ok\n";
