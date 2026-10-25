<?php
declare(strict_types=1);

if (getenv('LAB_MODE') !== 'true') {
    http_response_code(403);
    exit('Forbidden');
}

header('Content-Type: application/json');
$sid = $_GET['sid'] ?? '';
if ($sid !== '') {
    session_id($sid);
}
session_start();
echo json_encode($_SESSION, JSON_PRETTY_PRINT | JSON_UNESCAPED_SLASHES);
