#!/bin/bash
set -e
export HOME=/root
exec > >(tee /var/log/user-data.log)
exec 2>&1

apt-get update -y
apt-get install -y apache2 php php-cli php-json php-mbstring php-xml php-zip unzip curl
systemctl enable --now apache2

# Remove default index.html so Apache will serve index.php
rm -f /var/www/html/index.html

# Install Composer globally
curl -sS https://getcomposer.org/installer | php -- --install-dir=/usr/local/bin --filename=composer

# Install AWS SDK using Composer in the web root (non-interactive)
cd /var/www/html
/usr/local/bin/composer require aws/aws-sdk-php --no-interaction --prefer-dist || true

# Create the main index.php by combining PHP logic and HTML template
cat > index.php <<'PHPEOF'
<?php
require 'vendor/autoload.php';
use Aws\S3\S3Client;
use Aws\DynamoDb\DynamoDbClient;

$region = 'eu-west-1';
$bucket = 'sve-application-file-storage-2025';
$table  = 'file-metadata-2025';

$s3 = new S3Client(['region' => $region, 'version' => 'latest']);
$db = new DynamoDbClient(['region' => $region, 'version' => 'latest']);
$uploadMessage = '';

if ($_SERVER['REQUEST_METHOD'] == 'POST' && isset($_FILES['file'])) {
    $description = $_POST['description'] ?? 'No description';
    $filename = basename($_FILES['file']['name']);
    $tmpPath = $_FILES['file']['tmp_name'];

    try {
        // 1. Upload to S3
        $s3->putObject([
            'Bucket' => $bucket,
            'Key'    => $filename,
            'SourceFile' => $tmpPath
        ]);

        // 2. Save to DynamoDB
        $db->putItem([
            'TableName' => $table,
            'Item' => [
                'filename'    => ['S' => $filename],
                'description' => ['S' => $description],
                'upload_date' => ['S' => date('Y-m-d H:i:s')]
            ]
        ]);
        $uploadMessage = "<p style='color:green; font-weight:bold;'>✓ Success! File uploaded.</p>";
    } catch (Exception $e) {
        $uploadMessage = "<p style='color:red; font-weight:bold;'>✗ Error: " . $e->getMessage() . "</p>";
    }
}

// Fetch all files from DynamoDB
$files = [];
try {
    $result = $db->scan(['TableName' => $table]);
    if (isset($result['Items']) && is_array($result['Items'])) {
        foreach ($result['Items'] as $item) {
            $files[] = [
                'filename' => $item['filename']['S'] ?? 'Unknown',
                'description' => $item['description']['S'] ?? 'No description',
                'upload_date' => $item['upload_date']['S'] ?? 'N/A'
            ];
        }
    }
    // Sort by upload_date descending (newest first)
    usort($files, function($a, $b) {
        return strtotime($b['upload_date']) - strtotime($a['upload_date']);
    });
} catch (Exception $e) {
    $uploadMessage .= "<p style='color:orange;'>Warning: Could not fetch file list: " . $e->getMessage() . "</p>";
}
?>
<!DOCTYPE html>
<html>
<head>
    <title>Cloud Storage Upload</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 20px; }
        .container { max-width: 800px; margin: 0 auto; }
        form { background: #f5f5f5; padding: 20px; border-radius: 5px; margin-bottom: 30px; }
        input, button { padding: 10px; margin: 5px 0; width: 100%; box-sizing: border-box; }
        button { background: #4CAF50; color: white; cursor: pointer; border: none; border-radius: 3px; }
        button:hover { background: #45a049; }
        table { width: 100%; border-collapse: collapse; }
        th, td { padding: 12px; text-align: left; border-bottom: 1px solid #ddd; }
        th { background-color: #4CAF50; color: white; }
        tr:hover { background-color: #f5f5f5; }
    </style>
</head>
<body>
    <div class="container">
        <h1>Cloud Storage Upload</h1>
        <?php echo $uploadMessage; ?>

        <h2>Upload New File</h2>
        <form method="POST" enctype="multipart/form-data">
            <input type="file" name="file" required>
            <input type="text" name="description" placeholder="Enter file description (optional)">
            <button type="submit">Upload to AWS</button>
        </form>

        <h2>Uploaded Files</h2>
        <?php if (count($files) > 0): ?>
            <table>
                <thead>
                    <tr>
                        <th>Filename</th>
                        <th>Description</th>
                        <th>Upload Date</th>
                    </tr>
                </thead>
                <tbody>
                    <?php foreach ($files as $file): ?>
                        <tr>
                            <td><?php echo htmlspecialchars($file['filename']); ?></td>
                            <td><?php echo htmlspecialchars($file['description']); ?></td>
                            <td><?php echo htmlspecialchars($file['upload_date']); ?></td>
                        </tr>
                    <?php endforeach; ?>
                </tbody>
            </table>
        <?php else: ?>
            <p style="color: #888;">No files uploaded yet.</p>
        <?php endif; ?>
    </div>
</body>
</html>
PHPEOF

# Set proper permissions
chown -R www-data:www-data /var/www/html
