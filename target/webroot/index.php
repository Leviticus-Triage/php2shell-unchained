<?php
declare(strict_types=1);

if (getenv('LAB_MODE') !== 'true') {
    http_response_code(403);
    exit('Forbidden');
}

session_start();

if (isset($_GET['page'])) {
    // Intentionally vulnerable LFI for chained PoC testing in lab only.
    include $_GET['page'];
    return;
}

header('Content-Type: text/plain; charset=utf-8');
printf("PHP %s (%s)\n", PHP_VERSION, PHP_SAPI);
printf("session.upload_progress.enabled = %s\n", ini_get('session.upload_progress.enabled'));
printf("session.upload_progress.min_freq = %s\n", ini_get('session.upload_progress.min_freq'));
printf("memory_limit = %s\n", ini_get('memory_limit'));
echo "OK\n";
