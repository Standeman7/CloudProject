<?php
require '/var/www/html/vendor/autoload.php';

use Aws\S3\S3Client;
use Aws\DynamoDb\DynamoDbClient;
use Aws\Exception\AwsException;

$region = 'eu-west-1';
$bucket = 'sve-application-file-storage-2025';
$table  = 'file-metadata-2025';

$s3 = new S3Client([
    'region'  => $region,
    'version' => 'latest'
]);

$db = new DynamoDbClient([
    'region'  => $region,
    'version' => 'latest'
]);

$uploadMessage = null;
$uploadStatus  = null;

$allowedMimeTypes = [
    'text/plain',
    'application/pdf',
    'application/msword',
    'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
    'application/vnd.ms-powerpoint',
    'application/vnd.openxmlformats-officedocument.presentationml.presentation',
    'application/vnd.ms-excel',
    'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet'
];

$maxSize = 10 * 1024 * 1024; // 10MB

/* ================= DELETE FILE ================= */
if ($_SERVER['REQUEST_METHOD'] === 'POST' && isset($_POST['delete'])) {
    $filename = $_POST['filename'] ?? '';
    if ($filename) {
        try {
            $s3->deleteObject([
                'Bucket' => $bucket,
                'Key'    => $filename
            ]);

            $db->deleteItem([
                'TableName' => $table,
                'Key' => ['filename' => ['S' => $filename]]
            ]);

            $uploadMessage = 'File deleted successfully.';
            $uploadStatus = 'success';
        } catch (AwsException $e) {
            $uploadMessage = 'Delete failed: ' . $e->getAwsErrorMessage();
            $uploadStatus = 'error';
        }
    }
}

/* ================= FILE UPLOAD ================= */
if ($_SERVER['REQUEST_METHOD'] === 'POST' && isset($_FILES['file']) && !isset($_POST['delete'])) {
    $file = $_FILES['file'];
    $description = trim($_POST['description'] ?? 'No description');
    $mimeType = mime_content_type($file['tmp_name']);

    if ($file['error'] !== UPLOAD_ERR_OK) {
        $uploadMessage = 'File upload failed.';
        $uploadStatus = 'error';
    }
    elseif ($file['size'] > $maxSize) {
        $uploadMessage = 'File is too large (max 10MB).';
        $uploadStatus = 'error';
    }
    elseif (!in_array($mimeType, $allowedMimeTypes)) {
        $uploadMessage = 'Invalid file type. Only text, PDF, Word, PowerPoint and Excel files are allowed.';
        $uploadStatus = 'error';
    } else {
        try {
            $extension = pathinfo($file['name'], PATHINFO_EXTENSION);
            $safeName  = uniqid('file_', true) . '.' . $extension;

            $s3->putObject([
                'Bucket'      => $bucket,
                'Key'         => $safeName,
                'SourceFile'  => $file['tmp_name'],
                'ContentType' => $mimeType
            ]);

            $db->putItem([
                'TableName' => $table,
                'Item' => [
                    'filename'      => ['S' => $safeName],
                    'original_name' => ['S' => $file['name']],
                    'description'   => ['S' => $description],
                    'upload_date'   => ['S' => date(DATE_ATOM)]
                ]
            ]);

            $uploadMessage = 'File uploaded successfully.';
            $uploadStatus = 'success';
        } catch (AwsException $e) {
            $uploadMessage = 'Upload failed: ' . $e->getAwsErrorMessage();
            $uploadStatus = 'error';
        }
    }
}

/* ================= FETCH FILES ================= */
$files = [];
try {
    $result = $db->scan(['TableName' => $table]);
    foreach ($result['Items'] ?? [] as $item) {
        // Generate presigned URL for download
        $cmd = $s3->getCommand('GetObject', [
            'Bucket' => $bucket,
            'Key'    => $item['filename']['S']
        ]);
        $request = $s3->createPresignedRequest($cmd, '+10 minutes');

        $files[] = [
            'filename'      => $item['filename']['S'],
            'original_name' => $item['original_name']['S'] ?? $item['filename']['S'],
            'description'   => $item['description']['S'] ?? '',
            'upload_date'   => $item['upload_date']['S'] ?? '',
            'download_url'  => (string) $request->getUri()
        ];
    }

    usort($files, fn($a,$b) => strtotime($b['upload_date']) <=> strtotime($a['upload_date']));

} catch (AwsException $e) {
    $uploadMessage = 'Could not load file list.';
    $uploadStatus = 'warning';
}

/* ================= RENDER TEMPLATE ================= */
require 'template.php';
