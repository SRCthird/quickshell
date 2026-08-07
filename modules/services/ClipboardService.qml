pragma Singleton
import QtQuick
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
    
    readonly property string dbPath: Quickshell.dataPath("clipboard.db")
    readonly property string binaryDataDir: Quickshell.dataPath("clipboard-data")
    readonly property string schemaPath: Qt.resolvedUrl("clipboard_init.sql").toString().replace("file://", "")
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

    property Process initDbProcess: Process {
        running: false
        
        stderr: StdioCollector {
            onStreamFinished: {
                if (text.length > 0) console.warn("ClipboardService: DB Init Error: " + text)
            }
        }

        onExited: function(code) {
            if (code === 0) {
                root._initialized = true;
                ensureBinaryDataDir();
                Qt.callLater(root.list);
            } else {
                console.warn("ClipboardService: Failed to initialize database (Exit code: " + code + ")");
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

    property Process checkAndInsertProcess: Process {
        running: false

        stderr: StdioCollector {
            id: clipboardInsertError
            waitForEnd: true
        }

        onExited: function(code) {
            if (code === 0) {
                Qt.callLater(root.list);
            } else {
                console.warn("ClipboardService: clipboard insert failed with code:", code, clipboardInsertError.text);
            }

            root._finishClipboardCheck();
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

    property Process listProcess: Process {
        running: false
        
        stdout: StdioCollector {
            waitForEnd: true
            
            onStreamFinished: {
                var clipboardItems = [];
                
                var trimmedText = text.trim();
                if (trimmedText.length === 0) {
                    root.items = clipboardItems;
                    root.listCompleted();
                    root._operationInProgress = false;
                    return;
                }
                
                try {
                    var jsonArray = JSON.parse(trimmedText);
                    
                    for (var i = 0; i < jsonArray.length; i++) {
                        var item = jsonArray[i];
                        var isFile = item.mime_type === "text/uri-list";
                        
                        var preview = item.preview;
                        if (isFile && item.full_content) {
                            var uriContent = item.full_content.trim();
                            if (uriContent.startsWith("file://")) {
                                var filePath = uriContent.substring(7);
                                var fileName = filePath.split('/').pop();
                                fileName = root.decodeUriString(fileName);
                                preview = "[File] " + fileName;
                            }
                        } else if (item.is_image === 1) {
                            preview = "[Image]";
                        }
                        
                        clipboardItems.push({
                            id: item.id.toString(),
                            preview: preview,
                            fullContent: item.preview,
                            mime: item.mime_type,
                            isImage: item.is_image === 1,
                            isFile: isFile,
                            binaryPath: item.binary_path || "",
                            hash: item.content_hash || "",
                            size: item.size || 0,
                            createdAt: item.created_at || 0,
                            pinned: item.pinned === 1,
                            alias: item.alias || "",
                            displayIndex: item.display_index !== null ? item.display_index : -1
                        });
                    }
                } catch (e) {
                    console.warn("ClipboardService: Failed to parse clipboard items:", e);
                }
                
                root.items = clipboardItems;
                root.listCompleted();
                root._operationInProgress = false;
            }
        }
        
        stderr: StdioCollector {
            onStreamFinished: {
                if (text.length > 0) {
                    console.warn("ClipboardService: listProcess stderr:", text);
                }
            }
        }
        
        onExited: function(code) {
            if (code !== 0) {
                root.items = [];
                root.listCompleted();
                root._operationInProgress = false;
            }
        }
    }

    property Process insertProcess: Process {
        property string itemHash: ""
        property string itemContent: ""
        property string tmpFile: ""
        running: false
        
        stderr: StdioCollector {
            onStreamFinished: {
                if (text.length > 0) {
                    console.warn("ClipboardService: insertProcess stderr:", text);
                }
            }
        }
        
        onExited: function(code) {
            if (code === 0) {
                Qt.callLater(root.list);
            } else {
                console.warn("ClipboardService: insertProcess failed with code:", code);
                root._operationInProgress = false;
            }
            
            itemHash = "";
            itemContent = "";
            tmpFile = "";
        }
    }

    property Process getContentProcess: Process {
        property string itemId: ""
        running: false
        
        stdout: StdioCollector {
            waitForEnd: true
            
            onStreamFinished: {
                root.fullContentRetrieved(getContentProcess.itemId, text);
            }
        }
        
        onExited: function(code) {
            if (code !== 0) {
                root.fullContentRetrieved(getContentProcess.itemId, "");
            }
        }
    }

    property Process deleteProcess: Process {
        property string itemId: ""
        running: false
        
        stdout: StdioCollector {
            waitForEnd: true
            
            onStreamFinished: {
                var deletedHash = text.trim();
                if (deletedHash.length > 0) {
                    clearClipboardIfMatches.deletedHash = deletedHash;
                    clearClipboardIfMatches.running = true;
                }
            }
        }
        
        stderr: StdioCollector {
            onStreamFinished: {
                if (text.length > 0) {
                    console.warn("ClipboardService: deleteProcess stderr:", text);
                }
            }
        }
        
        onExited: function(code) {
            if (code === 0) {
                Qt.callLater(root.list);
            } else {
                root._operationInProgress = false;
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

    property Process clearProcess: Process {
        running: false
        
        onExited: function(code) {
            if (code === 0) {
                Qt.callLater(root.list);
                cleanBinaryDataDirProcess.running = true;
            }
        }
    }
    
    property Process togglePinProcess: Process {
        property string itemId: ""
        running: false
        
        stderr: StdioCollector {
            onStreamFinished: {
                if (text.length > 0) {
                    console.warn("ClipboardService: togglePinProcess stderr:", text);
                }
            }
        }
        
        onExited: function(code) {
            if (code === 0) {
                Qt.callLater(root.list);
            } else {
                root._operationInProgress = false;
            }
        }
    }
    
    property Process setAliasProcess: Process {
        property string itemId: ""
        running: false
        
        stderr: StdioCollector {
            onStreamFinished: {
                if (text.length > 0) {
                    console.warn("ClipboardService: setAliasProcess stderr:", text);
                }
            }
        }
        
        onExited: function(code) {
            if (code === 0) {
                Qt.callLater(root.list);
            } else {
                root._operationInProgress = false;
            }
        }
    }
    
    property Process cleanBinaryDataDirProcess: Process {
        running: false
        command: ["sh", "-c", 
            "cd '" + binaryDataDir + "' && " +
            "for f in *; do " +
            "  [ -f \"$f\" ] || continue; " +
            "  sqlite3 '" + dbPath + "' \"SELECT COUNT(*) FROM clipboard_items WHERE binary_path = '" + binaryDataDir + "/$f';\" | grep -q '^0$' && rm -f \"$f\"; " +
            "done"
        ]
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

    function initialize() {
        initDbProcess.command = ["sh", "-c", "sqlite3 " + dbPath + " < " + schemaPath];
        initDbProcess.running = true;
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

    function _sqlQuote(value) {
        return "'" + String(value === undefined || value === null ? "" : value).replace(/'/g, "''") + "'";
    }

    function _insertPendingClipboardItem() {
        var item = root._pendingClipboardItem;
        if (!item) {
            root._finishClipboardCheck();
            return;
        }

        var timestamp = Math.floor(Date.now() / 1000) * 1000;
        var fullContentSql = item.isImage
            ? "''"
            : "CAST(readfile(" + _sqlQuote(clipboardTempPath) + ") AS TEXT)";

        var sql = [
            "PRAGMA busy_timeout=5000;",
            "BEGIN TRANSACTION;",
            "INSERT INTO clipboard_items",
            "(content_hash, mime_type, preview, full_content, is_image, binary_path, size, pinned, display_index, created_at, updated_at)",
            "VALUES (" +
                _sqlQuote(item.hash) + ", " +
                _sqlQuote(item.mimeType) + ", " +
                _sqlQuote(item.preview) + ", " +
                fullContentSql + ", " +
                (item.isImage ? "1" : "0") + ", " +
                _sqlQuote(item.binaryPath) + ", " +
                Number(item.size || 0) + ", 0, 0, " +
                timestamp + ", " + timestamp +
            ")",
            "ON CONFLICT(content_hash) DO UPDATE SET",
            "updated_at = " + timestamp + ",",
            "display_index = 0;",
            "WITH reindexed AS (",
            "  SELECT id, ROW_NUMBER() OVER (ORDER BY updated_at DESC, id DESC) - 1 AS new_idx",
            "  FROM clipboard_items WHERE pinned = 0",
            ")",
            "UPDATE clipboard_items",
            "SET display_index = (",
            "  SELECT new_idx FROM reindexed WHERE reindexed.id = clipboard_items.id",
            ")",
            "WHERE pinned = 0;",
            "COMMIT;"
        ].join("\n");

        // No shell here: Quickshell passes the database path and SQL directly
        // as argv entries to sqlite3.
        checkAndInsertProcess.command = ["sqlite3", dbPath, sql];
        checkAndInsertProcess.running = true;
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

    property Process writeTmpProcess: Process {
        property string itemHash: ""
        property string itemContent: ""
        running: false
        
        stdout: StdioCollector {
            waitForEnd: true
            
            onStreamFinished: { }
        }
    }

    function list() {
        if (!_initialized) return;
        _operationInProgress = true;
        listProcess.command = ["sh", "-c", 
            "sqlite3 '" + dbPath + "' <<'EOSQL'\n.timeout 5000\n.mode json\nSELECT id, mime_type, preview, full_content, is_image, binary_path, content_hash, size, created_at, pinned, alias, display_index FROM clipboard_items ORDER BY pinned DESC, display_index ASC, updated_at DESC, id DESC LIMIT 100;\nEOSQL"
        ];
        listProcess.running = true;
    }

    function getFullContent(id) {
        if (!_initialized) return;
        getContentProcess.itemId = id;
        getContentProcess.command = ["sh", "-c", "sqlite3 '" + dbPath + "' '.timeout 5000' 'SELECT full_content FROM clipboard_items WHERE id = " + id + ";'"];
        getContentProcess.running = true;
    }

    function deleteItem(id) {
        if (!_initialized) return;
        _operationInProgress = true;
        deleteProcess.itemId = id;
        
        deleteProcess.command = ["sh", "-c", 
            "HASH=$(sqlite3 '" + dbPath + "' '.timeout 5000' 'SELECT content_hash FROM clipboard_items WHERE id = " + id + ";'); " +
            "sqlite3 '" + dbPath + "' '.timeout 5000' 'DELETE FROM clipboard_items WHERE id = " + id + ";'; " +
            "echo \"$HASH\""
        ];
        deleteProcess.running = true;
    }

    function clear() {
        if (!_initialized) return;
        clearProcess.command = ["sh", "-c", 
            "sqlite3 '" + dbPath + "' '.timeout 5000' 'DELETE FROM clipboard_items WHERE pinned = 0;'; " +
            "wl-copy --clear 2>/dev/null || true"
        ];
        clearProcess.running = true;
    }

    function togglePin(id) {
        if (!_initialized) return;
        _operationInProgress = true;
        togglePinProcess.itemId = id;
        togglePinProcess.command = ["sh", "-c", 
            "sqlite3 '" + dbPath + "' <<'EOSQL'\n" +
            ".timeout 5000\n" +
            "BEGIN TRANSACTION;\n" +
            "-- Toggle pin status\n" +
            "UPDATE clipboard_items SET pinned = CASE WHEN pinned = 1 THEN 0 ELSE 1 END WHERE id = " + id + ";\n" +
            "-- Get new pinned status\n" +
            "-- If item is now pinned (pinned=1), set its index to 0 and shift others\n" +
            "-- If item is now unpinned (pinned=0), set its index to 0 and shift others\n" +
            "UPDATE clipboard_items SET display_index = CASE \n" +
            "  WHEN id = " + id + " THEN 0\n" +
            "  ELSE display_index + 1\n" +
            "END WHERE pinned = (SELECT pinned FROM clipboard_items WHERE id = " + id + ");\n" +
            "-- Compact indices to remove gaps for both pinned and unpinned\n" +
            "WITH reindexed_pinned AS (\n" +
            "  SELECT id, ROW_NUMBER() OVER (ORDER BY display_index ASC, updated_at DESC, id DESC) - 1 AS new_idx\n" +
            "  FROM clipboard_items WHERE pinned = 1\n" +
            ")\n" +
            "UPDATE clipboard_items SET display_index = (SELECT new_idx FROM reindexed_pinned WHERE reindexed_pinned.id = clipboard_items.id) WHERE pinned = 1;\n" +
            "WITH reindexed_unpinned AS (\n" +
            "  SELECT id, ROW_NUMBER() OVER (ORDER BY display_index ASC, updated_at DESC, id DESC) - 1 AS new_idx\n" +
            "  FROM clipboard_items WHERE pinned = 0\n" +
            ")\n" +
            "UPDATE clipboard_items SET display_index = (SELECT new_idx FROM reindexed_unpinned WHERE reindexed_unpinned.id = clipboard_items.id) WHERE pinned = 0;\n" +
            "COMMIT;\n" +
            "EOSQL"
        ];
        togglePinProcess.running = true;
    }

    function setAlias(id, alias) {
        if (!_initialized) return;
        _operationInProgress = true;
        setAliasProcess.itemId = id;
        var escapedAlias = alias.replace(/'/g, "''");
        if (alias.trim() === "") {
            setAliasProcess.command = ["sh", "-c", "sqlite3 '" + dbPath + "' '.timeout 5000' 'UPDATE clipboard_items SET alias = NULL WHERE id = " + id + ";'"];
        } else {
            setAliasProcess.command = ["sh", "-c", "sqlite3 '" + dbPath + "' '.timeout 5000' \"UPDATE clipboard_items SET alias = '" + escapedAlias + "' WHERE id = " + id + ";\""];
        }
        setAliasProcess.running = true;
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

    function reorderItem(itemId, newIndex) {
        if (!_initialized) return;
        var item = null;
        for (var i = 0; i < items.length; i++) {
            if (items[i].id === itemId) {
                item = items[i];
                break;
            }
        }
        
        if (!item) return;
        var isPinned = item.pinned ? 1 : 0;
        if (newIndex < 0) newIndex = 0;
        reorderProcess.command = ["sh", "-c", 
            "sqlite3 '" + dbPath + "' <<'EOSQL'\n" +
            ".timeout 5000\n" +
            "BEGIN TRANSACTION;\n" +
            "-- Shift other items to make room\n" +
            "UPDATE clipboard_items SET display_index = display_index + 1 WHERE pinned = " + isPinned + " AND display_index >= " + newIndex + " AND id != " + itemId + ";\n" +
            "-- Set new index for target item\n" +
            "UPDATE clipboard_items SET display_index = " + newIndex + " WHERE id = " + itemId + ";\n" +
            "-- Compact indices to remove gaps\n" +
            "WITH reindexed AS (\n" +
            "  SELECT id, ROW_NUMBER() OVER (ORDER BY display_index ASC, updated_at DESC, id DESC) - 1 AS new_idx\n" +
            "  FROM clipboard_items WHERE pinned = " + isPinned + "\n" +
            ")\n" +
            "UPDATE clipboard_items SET display_index = (SELECT new_idx FROM reindexed WHERE reindexed.id = clipboard_items.id) WHERE pinned = " + isPinned + ";\n" +
            "COMMIT;\n" +
            "EOSQL"
        ];
        reorderProcess.running = true;
    }
    
    function moveItemUp(itemId) {
        var item = null;
        var currentIdx = -1;
        for (var i = 0; i < items.length; i++) {
            if (items[i].id === itemId) {
                item = items[i];
                currentIdx = i;
                break;
            }
        }
        
        if (!item || currentIdx < 0) return;
        if (currentIdx === 0) return;
        var prevItem = items[currentIdx - 1];
        if (prevItem.pinned !== item.pinned) return;
        var temp = items[currentIdx];
        items[currentIdx] = items[currentIdx - 1];
        items[currentIdx - 1] = temp;
        listCompleted();
        swapItems(itemId, prevItem.id);
    }
    
    function moveItemDown(itemId) {
        var item = null;
        var currentIdx = -1;
        for (var i = 0; i < items.length; i++) {
            if (items[i].id === itemId) {
                item = items[i];
                currentIdx = i;
                break;
            }
        }
        
        if (!item || currentIdx < 0) return;
        if (currentIdx >= items.length - 1) return;
        var nextItem = items[currentIdx + 1];
        if (nextItem.pinned !== item.pinned) return;
        var temp = items[currentIdx];
        items[currentIdx] = items[currentIdx + 1];
        items[currentIdx + 1] = temp;
        listCompleted();
        swapItems(itemId, nextItem.id);
    }
    
    function swapItems(itemId1, itemId2) {
        if (!_initialized) return;
        
        var cmd = "sqlite3 '" + dbPath + "' <<'EOSQL'\n" +
            ".timeout 5000\n" +
            "BEGIN TRANSACTION;\n" +
            "-- Reindex to ensure unique indices\n" +
            "WITH reindexed_pinned AS (\n" +
            "  SELECT id, ROW_NUMBER() OVER (ORDER BY display_index ASC, updated_at DESC, id DESC) - 1 AS new_idx\n" +
            "  FROM clipboard_items WHERE pinned = 1\n" +
            ")\n" +
            "UPDATE clipboard_items SET display_index = (SELECT new_idx FROM reindexed_pinned WHERE reindexed_pinned.id = clipboard_items.id) WHERE pinned = 1;\n" +
            "WITH reindexed_unpinned AS (\n" +
            "  SELECT id, ROW_NUMBER() OVER (ORDER BY display_index ASC, updated_at DESC, id DESC) - 1 AS new_idx\n" +
            "  FROM clipboard_items WHERE pinned = 0\n" +
            ")\n" +
            "UPDATE clipboard_items SET display_index = (SELECT new_idx FROM reindexed_unpinned WHERE reindexed_unpinned.id = clipboard_items.id) WHERE pinned = 0;\n" +
            "-- Create temp variables for the swap\n" +
            "CREATE TEMP TABLE IF NOT EXISTS swap_temp (idx1 INTEGER, idx2 INTEGER);\n" +
            "DELETE FROM swap_temp;\n" +
            "INSERT INTO swap_temp (idx1, idx2) \n" +
            "  SELECT \n" +
            "    (SELECT display_index FROM clipboard_items WHERE id = " + itemId1 + "),\n" +
            "    (SELECT display_index FROM clipboard_items WHERE id = " + itemId2 + ");\n" +
            "-- Perform the swap\n" +
            "UPDATE clipboard_items SET display_index = (SELECT idx2 FROM swap_temp) WHERE id = " + itemId1 + ";\n" +
            "UPDATE clipboard_items SET display_index = (SELECT idx1 FROM swap_temp) WHERE id = " + itemId2 + ";\n" +
            "-- Clean up\n" +
            "DELETE FROM swap_temp;\n" +
            "COMMIT;\n" +
            "EOSQL";
            
        var proc = Qt.createQmlObject('import Quickshell.Io; Process {}', root);
        proc.command = ["sh", "-c", cmd];
        
        proc.onExited.connect(function(code) {
             if (code === 0) {
                 Qt.callLater(root.list);
             } else {
                 console.warn("ClipboardService: dynamic swapProcess failed with code:", code);
             }
             proc.destroy();
        });
        
        proc.running = true;
    }
    

    property Process reorderProcess: Process {
        running: false
        
        stderr: StdioCollector {
            onStreamFinished: {
                if (text.length > 0) {
                    console.warn("ClipboardService: reorderProcess stderr:", text);
                }
            }
        }
        
        onExited: function(code) {
            if (code === 0) {
                Qt.callLater(root.list);
            }
        }
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
