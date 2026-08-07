pragma Singleton
import QtQuick
import QtQuick.LocalStorage
import Quickshell
import Quickshell.Io

QtObject {
    id: root

    property bool active: true
    property var items: []
    property var imageDataById: ({})
    property var linkPreviewCache: ({})
    property int revision: 0
    property bool _operationInProgress: false
    property var _db: null

    readonly property string databaseName: "shell-clipboard"
    readonly property string databaseVersion: "1.0"
    readonly property int databaseEstimatedSize: 64 * 1024 * 1024
    readonly property string binaryDataDir: Quickshell.dataPath("clipboard-data")
    readonly property string clipboardTempPath: binaryDataDir + "/.clipboard-check.tmp"

    property bool _initialized: false
    property bool _clipboardCheckPending: false
    property bool _clipboardCheckRunning: false
    property var _pendingClipboardItem: null

    property var suspendConnections: Connections {
        target: SuspendManager
        function onWakingUp() {
            wakeRestartTimer.restart();
        }
    }

    property var wakeRestartTimer: Timer {
        id: wakeRestartTimer
        interval: 2000
        repeat: false
        onTriggered: {
            if (root._initialized) {
                root.list();
                root.checkClipboard();
            }
        }
    }

    signal listCompleted()

    property Process clipboardWatcher: Process {
        running: root._initialized && !SuspendManager.isSuspending
        command: ["wl-paste", "--watch", "bash", "-c", "cat >/dev/null; printf 'CHANGED\\n'"]

        stdout: SplitParser {
            onRead: data => {
                if (data.trim() === "CHANGED") {
                    root.checkClipboard();
                }
            }
        }

        stderr: SplitParser {
            onRead: data => {
                if (data.length > 0 && !data.includes("No selection")) {
                    console.warn("ClipboardService: watcher stderr:", data);
                }
            }
        }

        onExited: function(code) {
            if (root._initialized && !SuspendManager.isSuspending) {
                console.warn("ClipboardService: watcher exited with code:", code, "- restarting...");
                Qt.callLater(function() {
                    clipboardWatcher.running = Qt.binding(function() {
                        return root._initialized && !SuspendManager.isSuspending;
                    });
                });
            }
        }
    }

    property Process ensureDirProcess: Process {
        running: false
    }

    property Process clipboardEnsureDirProcess: Process {
        running: false

        onExited: function(code) {
            if (code === 0) {
                clipboardTypesProcess.command = ["wl-paste", "--list-types"];
                clipboardTypesProcess.running = true;
            } else {
                console.warn("ClipboardService: failed to ensure clipboard data directory:", code);
                root._finishClipboardCheck();
            }
        }
    }

    property Process clipboardTypesProcess: Process {
        running: false

        stdout: StdioCollector {
            id: clipboardTypesOutput
            waitForEnd: true
        }

        stderr: StdioCollector {
            id: clipboardTypesError
            waitForEnd: true
        }

        onExited: function(code) {
            if (code !== 0) {
                if (clipboardTypesError.text.length > 0 && !clipboardTypesError.text.includes("No selection")) {
                    console.warn("ClipboardService: wl-paste --list-types failed:", clipboardTypesError.text);
                }
                root._finishClipboardCheck();
                return;
            }

            root._readPreferredClipboardType(clipboardTypesOutput.text);
        }
    }

    property Process clipboardReadProcess: Process {
        property string mimeType: ""
        running: false

        stdout: StdioCollector {
            id: clipboardReadOutput
            waitForEnd: true
        }

        stderr: StdioCollector {
            id: clipboardReadError
            waitForEnd: true
        }

        onExited: function(code) {
            if (code !== 0) {
                if (clipboardReadError.text.length > 0 && !clipboardReadError.text.includes("No selection")) {
                    console.warn("ClipboardService: wl-paste failed for", mimeType + ":", clipboardReadError.text);
                }
                root._finishClipboardCheck();
                return;
            }

            root._prepareClipboardItem(mimeType, clipboardReadOutput.text, clipboardReadOutput.data);
        }
    }

    property var clipboardTempFile: FileView {
        id: clipboardTempFile
        path: ""
        atomicWrites: true
        blockWrites: false
        printErrors: false

        onSaved: root._hashClipboardTempFile()

        onSaveFailed: function(error) {
            console.warn("ClipboardService: failed to write clipboard temp file:", error);
            root._finishClipboardCheck();
        }
    }

    property Process clipboardHashProcess: Process {
        running: false

        stdout: StdioCollector {
            id: clipboardHashOutput
            waitForEnd: true
        }

        stderr: StdioCollector {
            id: clipboardHashError
            waitForEnd: true
        }

        onExited: function(code) {
            if (code !== 0) {
                console.warn("ClipboardService: md5sum failed:", clipboardHashError.text);
                root._finishClipboardCheck();
                return;
            }

            var hash = clipboardHashOutput.text.trim().split(/\s+/)[0] || "";
            if (hash.length === 0) {
                console.warn("ClipboardService: md5sum returned an empty hash");
                root._finishClipboardCheck();
                return;
            }

            root._clipboardHashReady(hash);
        }
    }

    property Process clipboardImageMoveProcess: Process {
        running: false

        stderr: StdioCollector {
            id: clipboardImageMoveError
            waitForEnd: true
        }

        onExited: function(code) {
            if (code === 0) {
                root._insertPendingClipboardItem();
            } else {
                console.warn("ClipboardService: failed to store clipboard image:", clipboardImageMoveError.text);
                root._finishClipboardCheck();
            }
        }
    }

    property Process clipboardFileStatProcess: Process {
        running: false

        stdout: StdioCollector {
            id: clipboardFileStatOutput
            waitForEnd: true
        }

        onExited: function(code) {
            if (root._pendingClipboardItem) {
                root._pendingClipboardItem.size = code === 0
                    ? (parseInt(clipboardFileStatOutput.text.trim(), 10) || 0)
                    : 0;
            }
            root._insertPendingClipboardItem();
        }
    }

    property Process clipboardCleanupProcess: Process {
        running: false

        onExited: function(code) {
            root._pendingClipboardItem = null;
            root._clipboardCheckRunning = false;

            if (root._clipboardCheckPending) {
                root._clipboardCheckPending = false;
                Qt.callLater(root.checkClipboard);
            }
        }
    }

    property Process clearClipboardIfMatches: Process {
        property string deletedHash: ""
        running: false
        
        command: ["sh", "-c",
            "CURRENT_HASH=''; " +
            "if CONTENT=$(wl-paste --type text/uri-list 2>/dev/null); then " +
            "  CURRENT_HASH=$(printf '%s' \"$CONTENT\" | tr -d '\\r' | md5sum | cut -d' ' -f1); " +
            "elif IMAGE_MIME=$(wl-paste --list-types 2>/dev/null | grep '^image/' | head -1); [ -n \"$IMAGE_MIME\" ]; then " +
            "  CURRENT_HASH=$(wl-paste --type \"$IMAGE_MIME\" 2>/dev/null | md5sum | cut -d' ' -f1); " +
            "elif CONTENT=$(wl-paste --type 'text/plain;charset=utf-8' 2>/dev/null); then " +
            "  CURRENT_HASH=$(printf '%s' \"$CONTENT\" | md5sum | cut -d' ' -f1); " +
            "elif CONTENT=$(wl-paste --type text/plain 2>/dev/null); then " +
            "  CURRENT_HASH=$(printf '%s' \"$CONTENT\" | md5sum | cut -d' ' -f1); " +
            "fi; " +
            "if [ \"$CURRENT_HASH\" = '" + deletedHash + "' ]; then " +
            "  wl-copy --clear 2>/dev/null || true; " +
            "fi"
        ]
        
        stderr: StdioCollector {
            onStreamFinished: {
                if (text.length > 0 && !text.includes("No selection")) {
                    console.warn("ClipboardService: clearClipboardIfMatches stderr:", text);
                }
            }
        }
    }

    property Process clearClipboardProcess: Process {
        running: false
        command: ["wl-copy", "--clear"]

        stderr: StdioCollector {
            onStreamFinished: {
                if (text.length > 0 && !text.includes("No selection")) {
                    console.warn("ClipboardService: wl-copy --clear stderr:", text);
                }
            }
        }
    }

    property Process loadImageProcess: Process {
        property string itemId: ""
        property string mimeType: ""
        running: false
        
        stdout: StdioCollector {
            waitForEnd: true
            
            onStreamFinished: {
                if (text.length > 0) {
                    var cleanBase64 = text.replace(/\s/g, '');
                    var dataUrl = "data:" + loadImageProcess.mimeType + ";base64," + cleanBase64;
                    root.imageDataById[loadImageProcess.itemId] = dataUrl;
                    root.revision++;
                }
            }
        }
    }
    
    signal fullContentRetrieved(string itemId, string content)
    signal linkPreviewFetched(string url, var metadata, string itemId)
    
    function decodeUriString(str) {
        try {
            return decodeURIComponent(str);
        } catch (e) {
            return str;
        }
    }

    function _transaction(context, callback) {
        if (!root._db) return false;

        try {
            root._db.transaction(function(tx) {
                callback(tx);
            });
            return true;
        } catch (e) {
            console.warn("ClipboardService: database " + context + " failed:", e);
            return false;
        }
    }

    function _initializeSchema() {
        root._db.transaction(function(tx) {
            tx.executeSql("PRAGMA busy_timeout = 5000");

            tx.executeSql(
                "CREATE TABLE IF NOT EXISTS clipboard_items (" +
                "id INTEGER PRIMARY KEY AUTOINCREMENT, " +
                "content_hash TEXT NOT NULL UNIQUE, " +
                "mime_type TEXT NOT NULL DEFAULT 'text/plain', " +
                "preview TEXT NOT NULL, " +
                "full_content TEXT, " +
                "is_image INTEGER NOT NULL DEFAULT 0, " +
                "binary_path TEXT, " +
                "size INTEGER NOT NULL DEFAULT 0, " +
                "pinned INTEGER NOT NULL DEFAULT 0, " +
                "alias TEXT, " +
                "display_index INTEGER, " +
                "created_at INTEGER NOT NULL, " +
                "updated_at INTEGER NOT NULL" +
                ")"
            );

            tx.executeSql("CREATE INDEX IF NOT EXISTS idx_content_hash ON clipboard_items(content_hash)");
            tx.executeSql("CREATE INDEX IF NOT EXISTS idx_created_at ON clipboard_items(created_at DESC)");
            tx.executeSql("CREATE INDEX IF NOT EXISTS idx_is_image ON clipboard_items(is_image)");
            tx.executeSql("CREATE INDEX IF NOT EXISTS idx_pinned ON clipboard_items(pinned DESC)");
            tx.executeSql("CREATE INDEX IF NOT EXISTS idx_display_index ON clipboard_items(pinned DESC, display_index ASC)");
        });

        // FTS is not used by the current UI, but keep the existing schema feature when
        // the SQLite build behind Qt's QSQLITE driver has FTS5 enabled.
        try {
            root._db.transaction(function(tx) {
                tx.executeSql(
                    "CREATE VIRTUAL TABLE IF NOT EXISTS clipboard_fts USING fts5(" +
                    "preview, full_content, content=clipboard_items, content_rowid=id)"
                );

                // Recreate the triggers so old/incorrect trigger definitions cannot linger.
                tx.executeSql("DROP TRIGGER IF EXISTS clipboard_items_ai");
                tx.executeSql("DROP TRIGGER IF EXISTS clipboard_items_ad");
                tx.executeSql("DROP TRIGGER IF EXISTS clipboard_items_au");

                tx.executeSql(
                    "CREATE TRIGGER clipboard_items_ai AFTER INSERT ON clipboard_items BEGIN " +
                    "INSERT INTO clipboard_fts(rowid, preview, full_content) " +
                    "VALUES (new.id, new.preview, new.full_content); END"
                );
                tx.executeSql(
                    "CREATE TRIGGER clipboard_items_ad AFTER DELETE ON clipboard_items BEGIN " +
                    "INSERT INTO clipboard_fts(clipboard_fts, rowid, preview, full_content) " +
                    "VALUES ('delete', old.id, old.preview, old.full_content); END"
                );
                tx.executeSql(
                    "CREATE TRIGGER clipboard_items_au AFTER UPDATE ON clipboard_items BEGIN " +
                    "INSERT INTO clipboard_fts(clipboard_fts, rowid, preview, full_content) " +
                    "VALUES ('delete', old.id, old.preview, old.full_content); " +
                    "INSERT INTO clipboard_fts(rowid, preview, full_content) " +
                    "VALUES (new.id, new.preview, new.full_content); END"
                );

                // Creating external-content FTS triggers does not index pre-existing rows.
                tx.executeSql("INSERT INTO clipboard_fts(clipboard_fts) VALUES ('rebuild')");
            });
        } catch (e) {
            console.warn("ClipboardService: FTS5 unavailable; continuing without clipboard_fts:", e);
        }
    }

    function _reindexGroup(tx, pinned) {
        var rows = tx.executeSql(
            "SELECT id FROM clipboard_items " +
            "WHERE pinned = ? " +
            "ORDER BY CASE WHEN display_index IS NULL THEN 1 ELSE 0 END, " +
            "display_index ASC, updated_at DESC, id DESC",
            [pinned]
        );

        for (var i = 0; i < rows.rows.length; i++) {
            tx.executeSql(
                "UPDATE clipboard_items SET display_index = ? WHERE id = ?",
                [i, rows.rows.item(i).id]
            );
        }
    }

    function _reindexUnpinnedByRecency(tx) {
        var rows = tx.executeSql(
            "SELECT id FROM clipboard_items WHERE pinned = 0 " +
            "ORDER BY updated_at DESC, id DESC"
        );

        for (var i = 0; i < rows.rows.length; i++) {
            tx.executeSql(
                "UPDATE clipboard_items SET display_index = ? WHERE id = ?",
                [i, rows.rows.item(i).id]
            );
        }
    }

    function _removeFilesAsync(paths) {
        if (!paths || paths.length === 0) return;

        var seen = {};
        var command = ["rm", "-f", "--"];
        for (var i = 0; i < paths.length; i++) {
            var path = String(paths[i] || "");
            if (path.length === 0 || seen[path]) continue;
            seen[path] = true;
            command.push(path);
        }

        if (command.length === 3) return;

        var proc = Qt.createQmlObject('import Quickshell.Io; Process { running: false }', root);
        proc.command = command;
        proc.exited.connect(function(code) {
            if (code !== 0) {
                console.warn("ClipboardService: failed to remove stale clipboard data, exit code:", code);
            }
            proc.destroy();
        });
        proc.running = true;
    }

    function initialize() {
        if (root._initialized || root._db) return;

        try {
            root._db = LocalStorage.openDatabaseSync(
                root.databaseName,
                root.databaseVersion,
                "Shell Clipboard Database",
                root.databaseEstimatedSize
            );
            root._initializeSchema();
            root._initialized = true;
            root.ensureBinaryDataDir();
            Qt.callLater(root.list);
        } catch (e) {
            root._db = null;
            root._initialized = false;
            console.warn("ClipboardService: failed to initialize LocalStorage database:", e);
        }
    }

    function ensureBinaryDataDir() {
        ensureDirProcess.command = ["mkdir", "-p", binaryDataDir];
        ensureDirProcess.running = true;
    }

    function _readPreferredClipboardType(typeText) {
        var types = typeText.split(/\r?\n/).filter(function(value) {
            return value.length > 0;
        });

        var selectedMime = "";

        if (types.indexOf("text/uri-list") !== -1) {
            selectedMime = "text/uri-list";
        } else {
            for (var i = 0; i < types.length; i++) {
                if (types[i].startsWith("image/")) {
                    selectedMime = types[i];
                    break;
                }
            }

            if (selectedMime.length === 0 && types.indexOf("text/plain;charset=utf-8") !== -1) {
                selectedMime = "text/plain;charset=utf-8";
            }

            if (selectedMime.length === 0 && types.indexOf("text/plain") !== -1) {
                selectedMime = "text/plain";
            }
        }

        if (selectedMime.length === 0) {
            root._finishClipboardCheck();
            return;
        }

        clipboardReadProcess.mimeType = selectedMime;
        clipboardReadProcess.command = ["wl-paste", "--type", selectedMime];
        clipboardReadProcess.running = true;
    }

    function _normalizeClipboardText(content) {
        return String(content || "")
            .replace(/\r/g, "")
            .replace(/\n+$/, "");
    }

    function _clipboardPreview(content, isImage) {
        if (isImage) return "[Image]";
        if (content.length > 100) return content.substring(0, 97) + "...";
        return content;
    }

    function _clipboardTextLength(content) {
        try {
            return Array.from(content).length;
        } catch (e) {
            return content.length;
        }
    }

    function _prepareClipboardItem(sourceMime, textContent, binaryData) {
        var isImage = sourceMime.startsWith("image/");
        var content = isImage ? "" : _normalizeClipboardText(textContent);

        if (!isImage && content.length === 0) {
            root._finishClipboardCheck();
            return;
        }

        var storedMime = sourceMime.startsWith("text/plain") ? "text/plain" : sourceMime;

        root._pendingClipboardItem = {
            hash: "",
            mimeType: storedMime,
            isImage: isImage,
            content: content,
            preview: _clipboardPreview(content, isImage),
            binaryPath: "",
            size: isImage && binaryData ? binaryData.byteLength : _clipboardTextLength(content)
        };

        clipboardTempFile.path = clipboardTempPath;
        if (isImage) {
            clipboardTempFile.setData(binaryData);
        } else {
            clipboardTempFile.setText(content);
        }
    }

    function _hashClipboardTempFile() {
        if (!root._pendingClipboardItem) {
            root._finishClipboardCheck();
            return;
        }

        clipboardHashProcess.command = ["md5sum", clipboardTempPath];
        clipboardHashProcess.running = true;
    }

    function _imageExtension(mimeType) {
        switch (mimeType) {
        case "image/png": return "png";
        case "image/jpeg": return "jpg";
        case "image/gif": return "gif";
        case "image/webp": return "webp";
        case "image/bmp": return "bmp";
        case "image/svg+xml": return "svg";
        default: return "img";
        }
    }

    function _padNumber(value, width) {
        var result = String(value);
        while (result.length < width) result = "0" + result;
        return result;
    }

    function _newClipboardImagePath(mimeType, hash) {
        var now = new Date();
        var timestamp =
            now.getFullYear() +
            _padNumber(now.getMonth() + 1, 2) +
            _padNumber(now.getDate(), 2) + "_" +
            _padNumber(now.getHours(), 2) +
            _padNumber(now.getMinutes(), 2) +
            _padNumber(now.getSeconds(), 2) + "_" +
            _padNumber(now.getMilliseconds(), 3);

        return binaryDataDir + "/clipboard_" + timestamp + "_" + hash.substring(0, 8) + "." + _imageExtension(mimeType);
    }

    function _clipboardHashReady(hash) {
        if (!root._pendingClipboardItem) {
            root._finishClipboardCheck();
            return;
        }

        root._pendingClipboardItem.hash = hash;

        if (root._pendingClipboardItem.isImage) {
            var binaryPath = _newClipboardImagePath(root._pendingClipboardItem.mimeType, hash);
            root._pendingClipboardItem.binaryPath = binaryPath;
            clipboardTempFile.path = "";
            clipboardImageMoveProcess.command = ["mv", "-f", clipboardTempPath, binaryPath];
            clipboardImageMoveProcess.running = true;
            return;
        }

        if (root._pendingClipboardItem.mimeType === "text/uri-list") {
            var filePath = root._pendingClipboardItem.content;
            if (filePath.startsWith("file://")) filePath = filePath.substring(7);

            if (filePath.length > 0 && !filePath.includes("\n")) {
                clipboardFileStatProcess.command = ["stat", "-c", "%s", "--", filePath];
                clipboardFileStatProcess.running = true;
                return;
            }

            root._pendingClipboardItem.size = 0;
        }

        root._insertPendingClipboardItem();
    }

    function _insertPendingClipboardItem() {
        var item = root._pendingClipboardItem;
        if (!item) {
            root._finishClipboardCheck();
            return;
        }

        var timestamp = Math.floor(Date.now() / 1000) * 1000;
        var duplicateBinaryPath = "";

        var ok = root._transaction("insert", function(tx) {
            var existing = tx.executeSql(
                "SELECT id, pinned, binary_path FROM clipboard_items WHERE content_hash = ? LIMIT 1",
                [item.hash]
            );

            if (existing.rows.length > 0) {
                var row = existing.rows.item(0);
                var isPinned = Number(row.pinned) === 1;

                if (isPinned) {
                    tx.executeSql(
                        "UPDATE clipboard_items SET updated_at = ? WHERE id = ?",
                        [timestamp, row.id]
                    );
                } else {
                    tx.executeSql(
                        "UPDATE clipboard_items SET updated_at = ?, display_index = 0 WHERE id = ?",
                        [timestamp, row.id]
                    );
                    root._reindexUnpinnedByRecency(tx);
                }

                if (item.isImage && item.binaryPath && item.binaryPath !== String(row.binary_path || "")) {
                    duplicateBinaryPath = item.binaryPath;
                }
                return;
            }

            tx.executeSql(
                "INSERT INTO clipboard_items " +
                "(content_hash, mime_type, preview, full_content, is_image, binary_path, size, pinned, display_index, created_at, updated_at) " +
                "VALUES (?, ?, ?, ?, ?, ?, ?, 0, 0, ?, ?)",
                [
                    item.hash,
                    item.mimeType,
                    item.preview,
                    item.isImage ? "" : item.content,
                    item.isImage ? 1 : 0,
                    item.binaryPath,
                    Number(item.size || 0),
                    timestamp,
                    timestamp
                ]
            );

            root._reindexUnpinnedByRecency(tx);
        });

        if (duplicateBinaryPath.length > 0) {
            root._removeFilesAsync([duplicateBinaryPath]);
        }

        if (ok) {
            Qt.callLater(root.list);
        } else if (item.isImage && item.binaryPath) {
            // The image has already been moved out of the temp file at this point.
            // Remove it if the database transaction failed so it cannot become orphaned.
            root._removeFilesAsync([item.binaryPath]);
        }

        root._finishClipboardCheck();
    }

    function _finishClipboardCheck() {
        if (!root._clipboardCheckRunning) return;

        clipboardTempFile.path = "";
        clipboardCleanupProcess.command = ["rm", "-f", clipboardTempPath];

        if (!clipboardCleanupProcess.running) {
            clipboardCleanupProcess.running = true;
        }
    }

    function checkClipboard() {
        if (!_initialized) return;

        if (_clipboardCheckRunning) {
            _clipboardCheckPending = true;
            return;
        }

        _clipboardCheckRunning = true;
        _pendingClipboardItem = null;

        clipboardEnsureDirProcess.command = ["mkdir", "-p", binaryDataDir];
        clipboardEnsureDirProcess.running = true;
    }

    function list() {
        if (!root._initialized || !root._db) return;
        root._operationInProgress = true;

        var clipboardItems = [];
        var ok = root._transaction("list", function(tx) {
            var result = tx.executeSql(
                "SELECT id, mime_type, preview, " +
                "CASE WHEN mime_type = 'text/uri-list' THEN full_content ELSE NULL END AS full_content, " +
                "is_image, binary_path, content_hash, size, created_at, pinned, alias, display_index " +
                "FROM clipboard_items " +
                "ORDER BY pinned DESC, display_index ASC, updated_at DESC, id DESC LIMIT 100"
            );

            for (var i = 0; i < result.rows.length; i++) {
                var item = result.rows.item(i);
                var isFile = item.mime_type === "text/uri-list";
                var isImage = Number(item.is_image) === 1;

                var preview = String(item.preview || "");
                if (isFile && item.full_content) {
                    var uriContent = String(item.full_content).trim();
                    if (uriContent.startsWith("file://")) {
                        var filePath = uriContent.substring(7);
                        var fileName = filePath.split('/').pop();
                        fileName = root.decodeUriString(fileName);
                        preview = "[File] " + fileName;
                    }
                } else if (isImage) {
                    preview = "[Image]";
                }

                clipboardItems.push({
                    id: String(item.id),
                    preview: preview,
                    fullContent: String(item.preview || ""),
                    mime: String(item.mime_type || "text/plain"),
                    isImage: isImage,
                    isFile: isFile,
                    binaryPath: String(item.binary_path || ""),
                    hash: String(item.content_hash || ""),
                    size: Number(item.size || 0),
                    createdAt: Number(item.created_at || 0),
                    pinned: Number(item.pinned) === 1,
                    alias: String(item.alias || ""),
                    displayIndex: item.display_index !== null && item.display_index !== undefined
                        ? Number(item.display_index)
                        : -1
                });
            }
        });

        root.items = ok ? clipboardItems : [];
        root.listCompleted();
        root._operationInProgress = false;
    }

    function getFullContentValue(id) {
        if (!root._initialized || !root._db) return "";

        var content = "";
        root._transaction("get content", function(tx) {
            var result = tx.executeSql(
                "SELECT full_content FROM clipboard_items WHERE id = ? LIMIT 1",
                [id]
            );
            if (result.rows.length > 0) {
                var value = result.rows.item(0).full_content;
                content = value === null || value === undefined ? "" : String(value);
            }
        });
        return content;
    }

    function getFullContent(id) {
        if (!root._initialized) return;

        var itemId = String(id);
        var content = root.getFullContentValue(id);
        Qt.callLater(function() {
            root.fullContentRetrieved(itemId, content);
        });
    }

    function deleteItem(id) {
        if (!root._initialized || !root._db) return;
        root._operationInProgress = true;

        var deletedHash = "";
        var deletedBinaryPath = "";

        var ok = root._transaction("delete item", function(tx) {
            var result = tx.executeSql(
                "SELECT content_hash, binary_path, pinned FROM clipboard_items WHERE id = ? LIMIT 1",
                [id]
            );

            if (result.rows.length === 0) return;

            var row = result.rows.item(0);
            deletedHash = String(row.content_hash || "");
            deletedBinaryPath = String(row.binary_path || "");
            var pinned = Number(row.pinned) === 1 ? 1 : 0;

            tx.executeSql("DELETE FROM clipboard_items WHERE id = ?", [id]);
            root._reindexGroup(tx, pinned);
        });

        if (!ok) {
            root._operationInProgress = false;
            return;
        }

        if (deletedBinaryPath.length > 0) {
            root._removeFilesAsync([deletedBinaryPath]);
        }

        if (deletedHash.length > 0) {
            clearClipboardIfMatches.deletedHash = deletedHash;
            clearClipboardIfMatches.running = true;
        }

        Qt.callLater(root.list);
    }

    function clear() {
        if (!root._initialized || !root._db) return;

        var binaryPaths = [];
        var ok = root._transaction("clear history", function(tx) {
            var result = tx.executeSql(
                "SELECT binary_path FROM clipboard_items " +
                "WHERE pinned = 0 AND binary_path IS NOT NULL AND binary_path <> ''"
            );

            for (var i = 0; i < result.rows.length; i++) {
                binaryPaths.push(String(result.rows.item(i).binary_path || ""));
            }

            tx.executeSql("DELETE FROM clipboard_items WHERE pinned = 0");
        });

        if (!ok) return;

        root._removeFilesAsync(binaryPaths);
        clearClipboardProcess.running = true;
        Qt.callLater(root.list);
    }

    function togglePin(id) {
        if (!root._initialized || !root._db) return;
        root._operationInProgress = true;

        var ok = root._transaction("toggle pin", function(tx) {
            var result = tx.executeSql(
                "SELECT pinned FROM clipboard_items WHERE id = ? LIMIT 1",
                [id]
            );
            if (result.rows.length === 0) return;

            var oldPinned = Number(result.rows.item(0).pinned) === 1 ? 1 : 0;
            var newPinned = oldPinned === 1 ? 0 : 1;

            tx.executeSql(
                "UPDATE clipboard_items " +
                "SET display_index = COALESCE(display_index, 0) + 1 " +
                "WHERE pinned = ? AND id <> ?",
                [newPinned, id]
            );
            tx.executeSql(
                "UPDATE clipboard_items SET pinned = ?, display_index = 0 WHERE id = ?",
                [newPinned, id]
            );

            root._reindexGroup(tx, oldPinned);
            root._reindexGroup(tx, newPinned);
        });

        if (ok) {
            Qt.callLater(root.list);
        } else {
            root._operationInProgress = false;
        }
    }

    function setAlias(id, alias) {
        if (!root._initialized || !root._db) return;
        root._operationInProgress = true;

        var normalizedAlias = String(alias || "").trim();
        var ok = root._transaction("set alias", function(tx) {
            tx.executeSql(
                "UPDATE clipboard_items SET alias = ? WHERE id = ?",
                [normalizedAlias.length === 0 ? null : normalizedAlias, id]
            );
        });

        if (ok) {
            Qt.callLater(root.list);
        } else {
            root._operationInProgress = false;
        }
    }

    function decodeToDataUrl(id, mime) {
        if (imageDataById[id]) {
            return;
        }
        
        for (var i = 0; i < items.length; i++) {
            if (items[i].id === id) {
                var binaryPath = items[i].binaryPath;
                if (binaryPath && binaryPath.length > 0) {
                    loadImageProcess.itemId = id;
                    loadImageProcess.mimeType = mime;
                    loadImageProcess.command = ["base64", "-w", "0", binaryPath];
                    loadImageProcess.running = true;
                }
                break;
            }
        }
    }

    function getImageData(id) {
        return imageDataById[id] || "";
    }
    
    function _finishLinkPreview(url, itemId, metadata) {
        var responseUrl = metadata.request_url || metadata.url || url;

        if (!metadata.error && responseUrl) {
            root.linkPreviewCache[responseUrl] = metadata;
        }

        root.linkPreviewFetched(responseUrl, metadata, itemId);
    }

    function _httpGet(url, headers, timeoutMs, callback) {
        var request = new XMLHttpRequest();
        var finished = false;
        var timeoutTimer = Qt.createQmlObject(
            'import QtQuick; Timer { repeat: false }',
            root
        );

        timeoutTimer.interval = timeoutMs;
        timeoutTimer.triggered.connect(function() {
            if (finished) return;
            finished = true;
            request.abort();
            timeoutTimer.destroy();
            callback({
                status: 0,
                statusText: "Timeout",
                text: "",
                contentType: "",
                finalUrl: url
            });
        });

        request.onreadystatechange = function() {
            if (request.readyState !== XMLHttpRequest.DONE || finished) return;

            finished = true;
            timeoutTimer.stop();

            var finalUrl = request.responseURL && request.responseURL.length > 0
                ? request.responseURL
                : url;
            var contentType = request.getResponseHeader("Content-Type") || "";

            var result = {
                status: request.status,
                statusText: request.statusText || "",
                text: request.responseText || "",
                contentType: contentType,
                finalUrl: finalUrl
            };

            timeoutTimer.destroy();
            callback(result);
        };

        try {
            request.open("GET", url, true);

            if (headers) {
                for (var key in headers) {
                    try {
                        request.setRequestHeader(key, headers[key]);
                    } catch (e) {
                        // Some HTTP headers may be controlled by Qt/network backends.
                    }
                }
            }

            timeoutTimer.start();
            request.send();
        } catch (e) {
            if (!finished) {
                finished = true;
                timeoutTimer.stop();
                timeoutTimer.destroy();
                callback({
                    status: 0,
                    statusText: e.toString(),
                    text: "",
                    contentType: "",
                    finalUrl: url
                });
            }
        }
    }

    function _linkRequestHeaders() {
        return {
            "User-Agent": "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36",
            "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
            "Accept-Language": "en-US,en;q=0.5",
            "Accept-Encoding": "identity",
            "Range": "bytes=0-511999"
        };
    }

    function _isHttpUrl(url) {
        return /^https?:\/\/[^\/\s]+/i.test(url);
    }

    function _isYoutubeUrl(url) {
        return url.includes("youtube.com") || url.includes("youtu.be");
    }

    function _isTwitterUrl(url) {
        return url.includes("twitter.com") || url.includes("x.com");
    }

    function _extractYoutubeId(url) {
        var patterns = [
            /(?:youtube\.com\/watch\?v=|youtu\.be\/)([a-zA-Z0-9_-]{11})/,
            /youtube\.com\/embed\/([a-zA-Z0-9_-]{11})/,
            /youtube\.com\/v\/([a-zA-Z0-9_-]{11})/,
            /youtube\.com\/shorts\/([a-zA-Z0-9_-]{11})/
        ];

        for (var i = 0; i < patterns.length; i++) {
            var match = url.match(patterns[i]);
            if (match) return match[1];
        }

        return "";
    }

    function _decodeHtmlEntities(text) {
        if (!text) return "";

        var decoded = text
            .replace(/&amp;/gi, "&")
            .replace(/&lt;/gi, "<")
            .replace(/&gt;/gi, ">")
            .replace(/&quot;/gi, "\"")
            .replace(/&#39;|&apos;/gi, "'")
            .replace(/&nbsp;/gi, " ");

        decoded = decoded.replace(/&#(\d+);/g, function(match, value) {
            var code = parseInt(value, 10);
            if (isNaN(code)) return match;
            try {
                return String.fromCodePoint(code);
            } catch (e) {
                return String.fromCharCode(code);
            }
        });

        decoded = decoded.replace(/&#x([0-9a-f]+);/gi, function(match, value) {
            var code = parseInt(value, 16);
            if (isNaN(code)) return match;
            try {
                return String.fromCodePoint(code);
            } catch (e) {
                return String.fromCharCode(code);
            }
        });

        return decoded;
    }

    function _stripHtml(html) {
        return _decodeHtmlEntities(
            (html || "")
                .replace(/<script\b[^>]*>[\s\S]*?<\/script\s*>/gi, " ")
                .replace(/<style\b[^>]*>[\s\S]*?<\/style\s*>/gi, " ")
                .replace(/<[^>]+>/g, " ")
                .replace(/\s+/g, " ")
                .trim()
        );
    }

    function _parseTagAttributes(tag) {
        var attrs = {};
        var re = /([^\s=\/>]+)\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s"'=<>`]+))/g;
        var match;

        while ((match = re.exec(tag)) !== null) {
            var key = match[1].toLowerCase();
            var value = match[2] !== undefined
                ? match[2]
                : (match[3] !== undefined ? match[3] : match[4]);
            attrs[key] = _decodeHtmlEntities(value || "");
        }

        return attrs;
    }

    function _urlParts(url) {
        var match = String(url).match(/^(https?):\/\/([^\/?#]+)([^?#]*)/i);
        if (!match) return null;

        return {
            scheme: match[1].toLowerCase(),
            host: match[2],
            path: match[3] || "/"
        };
    }

    function _resolveUrl(baseUrl, value) {
        if (!value) return "";
        if (/^https?:\/\//i.test(value) || /^data:/i.test(value)) return value;

        var parts = _urlParts(baseUrl);
        if (!parts) return value;

        if (value.startsWith("//")) {
            return parts.scheme + ":" + value;
        }

        if (value.startsWith("/")) {
            return parts.scheme + "://" + parts.host + value;
        }

        var basePath = parts.path;
        var slash = basePath.lastIndexOf("/");
        var directory = slash >= 0 ? basePath.substring(0, slash + 1) : "/";

        var combined = directory + value;
        var segments = combined.split("/");
        var normalized = [];

        for (var i = 0; i < segments.length; i++) {
            var segment = segments[i];
            if (segment === "" || segment === ".") continue;
            if (segment === "..") {
                if (normalized.length > 0) normalized.pop();
            } else {
                normalized.push(segment);
            }
        }

        return parts.scheme + "://" + parts.host + "/" + normalized.join("/");
    }

    function _faviconScore(candidate) {
        var size = candidate.size;
        var sizeScore;

        if (size >= 32 && size <= 128) {
            sizeScore = size;
        } else if (size > 128) {
            sizeScore = 128 - Math.floor((size - 128) / 10);
        } else {
            sizeScore = size;
        }

        return candidate.priority * 10000 + sizeScore;
    }

    function _extractHtmlMetadata(html, requestUrl, finalUrl) {
        html = (html || "").substring(0, 500 * 1024);

        var metadata = {
            title: "",
            description: "",
            image: "",
            url: "",
            site_name: "",
            type: "website",
            favicon: ""
        };
        var faviconCandidates = [];

        var titleMatch = html.match(/<title\b[^>]*>([\s\S]*?)<\/title\s*>/i);
        if (titleMatch) {
            metadata.title = _stripHtml(titleMatch[1]);
        }

        var metaRe = /<meta\b(?:[^>"\']|"[^"]*"|\'[^\']*\')*>/gi;
        var tag;
        while ((tag = metaRe.exec(html)) !== null) {
            var attrs = _parseTagAttributes(tag[0]);
            var content = attrs.content || "";
            if (!content) continue;

            var prop = (attrs.property || "").toLowerCase();
            var name = (attrs.name || "").toLowerCase();

            if (prop === "og:title") {
                metadata.title = content;
            } else if (prop === "og:description") {
                metadata.description = content;
            } else if (prop === "og:image") {
                metadata.image = content;
            } else if (prop === "og:url") {
                metadata.url = content;
            } else if (prop === "og:site_name") {
                metadata.site_name = content;
            } else if (prop === "og:type") {
                metadata.type = content;
            }

            if (name === "twitter:title" && !metadata.title) {
                metadata.title = content;
            } else if (name === "twitter:description" && !metadata.description) {
                metadata.description = content;
            } else if (name === "twitter:image" && !metadata.image) {
                metadata.image = content;
            } else if (name === "description" && !metadata.description) {
                metadata.description = content;
            }
        }

        var linkRe = /<link\b(?:[^>"\']|"[^"]*"|\'[^\']*\')*>/gi;
        while ((tag = linkRe.exec(html)) !== null) {
            var linkAttrs = _parseTagAttributes(tag[0]);
            var rel = (linkAttrs.rel || "").toLowerCase();
            var href = linkAttrs.href || "";
            var sizes = linkAttrs.sizes || "";
            var linkType = (linkAttrs.type || "").toLowerCase();

            if (!href || rel.indexOf("icon") === -1) continue;

            var size = 0;
            var sizeMatch = sizes.match(/^(\d+)x\d+/i);
            if (sizeMatch) size = parseInt(sizeMatch[1], 10) || 0;

            var hrefLower = href.toLowerCase();
            var priority = 1;
            if (hrefLower.includes(".svg") || linkType.includes("svg")) {
                priority = 3;
            } else if (hrefLower.includes(".png") || linkType.includes("png")) {
                priority = 2;
            }

            faviconCandidates.push({
                href: href,
                size: size,
                priority: priority
            });

            if (!metadata.favicon) metadata.favicon = href;
        }

        if (faviconCandidates.length > 0) {
            faviconCandidates.sort(function(a, b) {
                return _faviconScore(b) - _faviconScore(a);
            });
            metadata.favicon = faviconCandidates[0].href;
        }

        var effectiveUrl = finalUrl || requestUrl;
        var parts = _urlParts(effectiveUrl);

        if (metadata.image) {
            metadata.image = _resolveUrl(effectiveUrl, metadata.image);
        }

        if (metadata.favicon) {
            metadata.favicon = _resolveUrl(effectiveUrl, metadata.favicon);
        } else if (parts) {
            metadata.favicon = parts.scheme + "://" + parts.host + "/favicon.ico";
        }

        if (!metadata.url) {
            metadata.url = requestUrl;
        }

        metadata.request_url = requestUrl;

        if (!metadata.site_name && parts) {
            metadata.site_name = parts.host;
        }

        return metadata;
    }

    function _fetchGenericLinkPreview(url, itemId) {
        _httpGet(url, _linkRequestHeaders(), 5000, function(response) {
            if (response.status < 200 || response.status >= 400) {
                _finishLinkPreview(url, itemId, {
                    error: response.status > 0
                        ? "HTTP " + response.status
                        : "Connection failed: " + response.statusText,
                    url: url,
                    request_url: url
                });
                return;
            }

            var contentType = (response.contentType || "").toLowerCase();
            if (contentType && !contentType.includes("text/html") && !contentType.includes("application/xhtml+xml")) {
                _finishLinkPreview(url, itemId, {
                    error: "Not an HTML page",
                    url: url,
                    request_url: url
                });
                return;
            }

            try {
                var metadata = _extractHtmlMetadata(
                    response.text,
                    url,
                    response.finalUrl
                );
                _finishLinkPreview(url, itemId, metadata);
            } catch (e) {
                _finishLinkPreview(url, itemId, {
                    error: "Failed to parse: " + e,
                    url: url,
                    request_url: url
                });
            }
        });
    }

    function _fetchYoutubeLinkPreview(url, itemId) {
        var videoId = _extractYoutubeId(url);
        if (!videoId) {
            _fetchGenericLinkPreview(url, itemId);
            return;
        }

        var endpoint =
            "https://www.youtube.com/oembed?url=" +
            encodeURIComponent("https://www.youtube.com/watch?v=" + videoId) +
            "&format=json";

        _httpGet(endpoint, null, 5000, function(response) {
            if (response.status >= 200 && response.status < 400) {
                try {
                    var data = JSON.parse(response.text);
                    var thumbnail = data.thumbnail_url || "";

                    if (thumbnail.includes("hqdefault")) {
                        thumbnail = thumbnail.replace("hqdefault", "maxresdefault");
                    }

                    _finishLinkPreview(url, itemId, {
                        title: data.title || "",
                        description: data.author_name || "Unknown",
                        image: thumbnail,
                        url: url,
                        request_url: url,
                        site_name: "YouTube",
                        type: "video",
                        favicon: "https://www.youtube.com/s/desktop/9c0f82da/img/favicon_144x144.png",
                        author: data.author_name || "",
                        video_id: videoId
                    });
                    return;
                } catch (e) {
                    // Fall through to regular page metadata.
                }
            }

            _fetchGenericLinkPreview(url, itemId);
        });
    }

    function _fetchTwitterLinkPreview(url, itemId) {
        var endpoint = "https://publish.twitter.com/oembed?url=" + encodeURIComponent(url);

        _httpGet(endpoint, null, 5000, function(response) {
            if (response.status >= 200 && response.status < 400) {
                try {
                    var data = JSON.parse(response.text);
                    _finishLinkPreview(url, itemId, {
                        title: data.author_name || "Tweet",
                        description: _stripHtml(data.html || ""),
                        image: "",
                        url: url,
                        request_url: url,
                        site_name: "X (Twitter)",
                        type: "article",
                        favicon: "https://abs.twimg.com/favicons/twitter.3.ico",
                        author: data.author_name || ""
                    });
                    return;
                } catch (e) {
                    // Fall through to regular page metadata.
                }
            }

            _fetchGenericLinkPreview(url, itemId);
        });
    }

    function fetchLinkPreview(url, itemId) {
        if (!_initialized) return;

        if (linkPreviewCache[url]) {
            Qt.callLater(function() {
                root.linkPreviewFetched(url, linkPreviewCache[url], itemId);
            });
            return;
        }

        if (!_isHttpUrl(url)) {
            Qt.callLater(function() {
                root.linkPreviewFetched(url, {
                    error: "Invalid URL",
                    url: url,
                    request_url: url
                }, itemId);
            });
            return;
        }

        if (_isYoutubeUrl(url)) {
            _fetchYoutubeLinkPreview(url, itemId);
        } else if (_isTwitterUrl(url)) {
            _fetchTwitterLinkPreview(url, itemId);
        } else {
            _fetchGenericLinkPreview(url, itemId);
        }
    }

    function _orderedGroupIds(tx, pinned) {
        var result = tx.executeSql(
            "SELECT id FROM clipboard_items WHERE pinned = ? " +
            "ORDER BY CASE WHEN display_index IS NULL THEN 1 ELSE 0 END, " +
            "display_index ASC, updated_at DESC, id DESC",
            [pinned]
        );

        var ids = [];
        for (var i = 0; i < result.rows.length; i++) {
            ids.push(String(result.rows.item(i).id));
        }
        return ids;
    }

    function _writeGroupOrder(tx, ids) {
        for (var i = 0; i < ids.length; i++) {
            tx.executeSql(
                "UPDATE clipboard_items SET display_index = ? WHERE id = ?",
                [i, ids[i]]
            );
        }
    }

    function reorderItem(itemId, newIndex) {
        if (!root._initialized || !root._db) return;

        var item = null;
        for (var i = 0; i < root.items.length; i++) {
            if (root.items[i].id === String(itemId)) {
                item = root.items[i];
                break;
            }
        }
        if (!item) return;

        var pinned = item.pinned ? 1 : 0;
        var targetId = String(itemId);
        var ok = root._transaction("reorder item", function(tx) {
            var ids = root._orderedGroupIds(tx, pinned);
            var oldIndex = ids.indexOf(targetId);
            if (oldIndex < 0) return;

            ids.splice(oldIndex, 1);
            var targetIndex = Math.max(0, Math.min(Number(newIndex) || 0, ids.length));
            ids.splice(targetIndex, 0, targetId);
            root._writeGroupOrder(tx, ids);
        });

        if (ok) Qt.callLater(root.list);
    }

    function moveItemUp(itemId) {
        var item = null;
        var currentIdx = -1;
        for (var i = 0; i < root.items.length; i++) {
            if (root.items[i].id === String(itemId)) {
                item = root.items[i];
                currentIdx = i;
                break;
            }
        }

        if (!item || currentIdx <= 0) return;
        var prevItem = root.items[currentIdx - 1];
        if (prevItem.pinned !== item.pinned) return;

        var temp = root.items[currentIdx];
        root.items[currentIdx] = root.items[currentIdx - 1];
        root.items[currentIdx - 1] = temp;
        root.listCompleted();
        root.swapItems(itemId, prevItem.id);
    }

    function moveItemDown(itemId) {
        var item = null;
        var currentIdx = -1;
        for (var i = 0; i < root.items.length; i++) {
            if (root.items[i].id === String(itemId)) {
                item = root.items[i];
                currentIdx = i;
                break;
            }
        }

        if (!item || currentIdx < 0 || currentIdx >= root.items.length - 1) return;
        var nextItem = root.items[currentIdx + 1];
        if (nextItem.pinned !== item.pinned) return;

        var temp = root.items[currentIdx];
        root.items[currentIdx] = root.items[currentIdx + 1];
        root.items[currentIdx + 1] = temp;
        root.listCompleted();
        root.swapItems(itemId, nextItem.id);
    }

    function swapItems(itemId1, itemId2) {
        if (!root._initialized || !root._db) return;

        var id1 = String(itemId1);
        var id2 = String(itemId2);
        var ok = root._transaction("swap items", function(tx) {
            var result = tx.executeSql(
                "SELECT id, pinned FROM clipboard_items WHERE id IN (?, ?)",
                [itemId1, itemId2]
            );
            if (result.rows.length !== 2) return;

            var pinned1 = null;
            var pinned2 = null;
            for (var i = 0; i < result.rows.length; i++) {
                var row = result.rows.item(i);
                if (String(row.id) === id1) pinned1 = Number(row.pinned) === 1 ? 1 : 0;
                if (String(row.id) === id2) pinned2 = Number(row.pinned) === 1 ? 1 : 0;
            }
            if (pinned1 === null || pinned2 === null || pinned1 !== pinned2) return;

            var ids = root._orderedGroupIds(tx, pinned1);
            var index1 = ids.indexOf(id1);
            var index2 = ids.indexOf(id2);
            if (index1 < 0 || index2 < 0) return;

            var temp = ids[index1];
            ids[index1] = ids[index2];
            ids[index2] = temp;
            root._writeGroupOrder(tx, ids);
        });

        if (ok) Qt.callLater(root.list);
    }

    property Process emojiTypeProcess: Process {
        running: false
        
        stderr: StdioCollector {
            onStreamFinished: {
                if (text.length > 0) {
                    console.warn("ClipboardService: emojiTypeProcess stderr:", text);
                }
            }
        }
        
        onExited: function(code) {
            if (code !== 0) {
                console.warn("ClipboardService: emojiTypeProcess failed with code:", code);
            }
        }
    }
    
    property Timer emojiTypeTimer: Timer {
        interval: 250
        repeat: false
        onTriggered: {
            emojiTypeProcess.command = ["wtype", "-M", "ctrl", "-P", "v", "-p", "v", "-m", "ctrl"];
            emojiTypeProcess.running = true;
        }
    }
    
    function copyAndTypeEmoji(emojiText) {
        var copyCmd = ["bash", "-c", "echo -n '" + emojiText.replace(/'/g, "'\\''") + "' | wl-copy"];
        var copyProc = Qt.createQmlObject('import Quickshell.Io; Process {}', root);
        copyProc.command = copyCmd;
        copyProc.running = true;
        emojiTypeTimer.start();
    }

    Component.onCompleted: {
        Qt.callLater(() => initialize());
    }
}
