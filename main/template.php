<!DOCTYPE html>
<html>
<head>
    <title>Cloud Storage Upload</title>
    <link rel="stylesheet" href="style.css">
</head>
<body>
<div class="container">

    <h1>Cloud Storage Upload</h1>

    <?php if ($uploadMessage): ?>
        <div class="alert <?= htmlspecialchars($uploadStatus) ?>">
            <?= htmlspecialchars($uploadMessage) ?>
        </div>
    <?php endif; ?>

    <h2>Upload New File</h2>
    <form method="POST" enctype="multipart/form-data">
        <input type="file" name="file" required>
        <input type="text" name="description" placeholder="Enter file description (optional)">
        <button type="submit">Upload to AWS</button>
    </form>

    <h2>Uploaded Files</h2>

    <?php if ($files): ?>
        <table>
            <thead>
                <tr>
                    <th>Filename</th>
                    <th>Description</th>
                    <th>Upload Date</th>
                    <th>Actions</th>
                </tr>
            </thead>
            <tbody>
                <?php foreach ($files as $file): ?>
                    <tr>
                        <td><?= htmlspecialchars($file['original_name']) ?></td>
                        <td><?= htmlspecialchars($file['description']) ?></td>
                        <td><?= date('Y-m-d H:i', strtotime($file['upload_date'])) ?></td>
                        <td class="actions">
                            <a href="<?= htmlspecialchars($file['download_url']) ?>"
                               class="btn download"
                               target="_blank"
                               rel="noopener">
                                Download
                            </a>

                            <form method="POST" style="display:inline;"
                                  onsubmit="return confirm('Delete this file?');">
                                <input type="hidden" name="filename"
                                       value="<?= htmlspecialchars($file['filename']) ?>">
                                <button type="submit" name="delete" class="btn delete">
                                    Delete
                                </button>
                            </form>
                        </td>
                    </tr>
                <?php endforeach; ?>
            </tbody>
        </table>
    <?php else: ?>
        <p class="muted">No files uploaded yet.</p>
    <?php endif; ?>

</div>
</body>
</html>
