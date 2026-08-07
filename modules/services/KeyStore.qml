pragma Singleton

import QtQuick
import QtQuick.LocalStorage
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    property var keyCache: ({})
    property bool initialized: false

    property var database: null

    readonly property string databaseName: "KeyStore"
    readonly property string databaseVersion: "1.0"
    readonly property string fallbackMachineKey: "shell-fallback-salt-82741"

    signal keysChanged

    FileView {
        id: machineIdFile

        path: "/etc/machine-id"
        blockLoading: true
        printErrors: false
    }

    Component.onCompleted: initialize()

    function initialize() {
        try {
            database = LocalStorage.openDatabaseSync(
                databaseName,
                databaseVersion,
                "API key storage",
                1024 * 1024
            );

            database.transaction(function(tx) {
                tx.executeSql(`
                    CREATE TABLE IF NOT EXISTS api_keys (
                        provider TEXT PRIMARY KEY,
                        api_key TEXT NOT NULL,
                        endpoint TEXT DEFAULT '',
                        custom_curl TEXT DEFAULT ''
                    )
                `);
            });

            refreshKeys();
        } catch (e) {
            console.warn("KeyStore: Failed to initialize database:", e);
            initialized = false;
        }
    }

    function ensureDatabase() {
        try {
            if (database === null) {
                database = LocalStorage.openDatabaseSync(
                    databaseName,
                    databaseVersion,
                    "API key storage",
                    1024 * 1024
                );
            }

            database.transaction(function(tx) {
                tx.executeSql(
                    "CREATE TABLE IF NOT EXISTS api_keys (" +
                    "provider TEXT PRIMARY KEY, " +
                    "api_key TEXT NOT NULL, " +
                    "endpoint TEXT DEFAULT '', " +
                    "custom_curl TEXT DEFAULT ''" +
                    ")"
                );
            });

            return true;
        } catch (e) {
            console.warn("KeyStore: Failed to open database:", e);
            return false;
        }
    }

    function getMachineKey() {
        try {
            let value = machineIdFile.text().trim();

            if (value.length > 0)
                return value;
        } catch (e) {
            console.warn("KeyStore: Failed to read /etc/machine-id:", e);
        }

        return fallbackMachineKey;
    }

    function utf8Encode(text) {
        let bytes = [];

        for (let i = 0; i < text.length; ++i) {
            let code = text.charCodeAt(i);

            if (code < 0x80) {
                bytes.push(code);
            } else if (code < 0x800) {
                bytes.push(
                    0xc0 | (code >> 6),
                    0x80 | (code & 0x3f)
                );
            } else if (
                code >= 0xd800 &&
                code <= 0xdbff &&
                i + 1 < text.length
            ) {
                let low = text.charCodeAt(i + 1);

                if (low >= 0xdc00 && low <= 0xdfff) {
                    let codePoint =
                        0x10000 +
                        ((code - 0xd800) << 10) +
                        (low - 0xdc00);

                    bytes.push(
                        0xf0 | (codePoint >> 18),
                        0x80 | ((codePoint >> 12) & 0x3f),
                        0x80 | ((codePoint >> 6) & 0x3f),
                        0x80 | (codePoint & 0x3f)
                    );

                    ++i;
                } else {
                    bytes.push(0xef, 0xbf, 0xbd);
                }
            } else {
                bytes.push(
                    0xe0 | (code >> 12),
                    0x80 | ((code >> 6) & 0x3f),
                    0x80 | (code & 0x3f)
                );
            }
        }

        return bytes;
    }

    function utf8Decode(bytes) {
        let result = "";

        for (let i = 0; i < bytes.length;) {
            let b0 = bytes[i++];

            if (b0 < 0x80) {
                result += String.fromCharCode(b0);
                continue;
            }

            if ((b0 & 0xe0) === 0xc0) {
                if (i >= bytes.length)
                    return "";

                let b1 = bytes[i++];

                if ((b1 & 0xc0) !== 0x80)
                    return "";

                let code =
                    ((b0 & 0x1f) << 6) |
                    (b1 & 0x3f);

                result += String.fromCharCode(code);
                continue;
            }

            if ((b0 & 0xf0) === 0xe0) {
                if (i + 1 >= bytes.length)
                    return "";

                let b1 = bytes[i++];
                let b2 = bytes[i++];

                if (
                    (b1 & 0xc0) !== 0x80 ||
                    (b2 & 0xc0) !== 0x80
                )
                    return "";

                let code =
                    ((b0 & 0x0f) << 12) |
                    ((b1 & 0x3f) << 6) |
                    (b2 & 0x3f);

                result += String.fromCharCode(code);
                continue;
            }

            if ((b0 & 0xf8) === 0xf0) {
                if (i + 2 >= bytes.length)
                    return "";

                let b1 = bytes[i++];
                let b2 = bytes[i++];
                let b3 = bytes[i++];

                if (
                    (b1 & 0xc0) !== 0x80 ||
                    (b2 & 0xc0) !== 0x80 ||
                    (b3 & 0xc0) !== 0x80
                )
                    return "";

                let codePoint =
                    ((b0 & 0x07) << 18) |
                    ((b1 & 0x3f) << 12) |
                    ((b2 & 0x3f) << 6) |
                    (b3 & 0x3f);

                codePoint -= 0x10000;

                result += String.fromCharCode(
                    0xd800 | (codePoint >> 10),
                    0xdc00 | (codePoint & 0x3ff)
                );

                continue;
            }

            return "";
        }

        return result;
    }

    function xorCrypt(data, key) {
        let result = [];

        if (key.length === 0)
            return result;

        for (let i = 0; i < data.length; ++i)
            result.push(data[i] ^ key[i % key.length]);

        return result;
    }

    function bytesToHex(bytes) {
        let result = "";

        for (let i = 0; i < bytes.length; ++i) {
            let value = bytes[i].toString(16);

            if (value.length < 2)
                value = "0" + value;

            result += value;
        }

        return result;
    }

    function hexToBytes(hex) {
        if (
            hex.length % 2 !== 0 ||
            !/^[0-9a-fA-F]*$/.test(hex)
        )
            return null;

        let bytes = [];

        for (let i = 0; i < hex.length; i += 2)
            bytes.push(parseInt(hex.substring(i, i + 2), 16));

        return bytes;
    }

    function encrypt(text) {
        let data = utf8Encode(text);
        let key = utf8Encode(getMachineKey());

        return bytesToHex(xorCrypt(data, key));
    }

    function decrypt(hex) {
        try {
            let data = hexToBytes(hex);

            if (data === null)
                return "";

            let key = utf8Encode(getMachineKey());
            let decrypted = xorCrypt(data, key);

            return utf8Decode(decrypted);
        } catch (e) {
            console.warn("KeyStore: Failed to decrypt key:", e);
            return "";
        }
    }

    function refreshKeys() {
        if (!ensureDatabase())
            return false;

        try {
            let cache = {};

            database.transaction(function(tx) {
                let result = tx.executeSql(
                    "SELECT provider, api_key, endpoint, custom_curl FROM api_keys"
                );

                for (let i = 0; i < result.rows.length; ++i) {
                    let row = result.rows.item(i);

                    cache[row.provider] = {
                        api_key: decrypt(row.api_key),
                        endpoint: row.endpoint || "",
                        custom_curl: row.custom_curl || ""
                    };
                }
            });

            keyCache = cache;
            initialized = true;
            keysChanged();

            return true;
        } catch (e) {
            console.warn("KeyStore: Failed to refresh keys:", e);
            return false;
        }
    }

    function getKey(provider) {
        if (!provider)
            return "";

        let entry = keyCache[provider];
        return entry ? entry.api_key : "";
    }

    function getEndpoint(provider) {
        if (!provider)
            return "";

        let entry = keyCache[provider];
        return entry ? entry.endpoint : "";
    }

    function getCustomCurl(provider) {
        if (!provider)
            return "";

        let entry = keyCache[provider];
        return entry ? entry.custom_curl : "";
    }

    function hasKey(provider) {
        return (
            keyCache[provider] !== undefined &&
            keyCache[provider].api_key !== ""
        );
    }

    function setKey(provider, apiKey, endpoint, customCurl) {
        if (!provider) {
            console.warn("KeyStore: Cannot set key without provider");
            return false;
        }

        if (!ensureDatabase())
            return false;

        endpoint = endpoint || "";
        customCurl = customCurl || "";

        try {
            database.transaction(function(tx) {
                tx.executeSql(`
                    INSERT OR REPLACE INTO api_keys
                        (provider, api_key, endpoint, custom_curl)
                    VALUES (?, ?, ?, ?)
                `, [
                    provider,
                    encrypt(apiKey),
                    endpoint,
                    customCurl
                ]);
            });

            refreshKeys();
            return true;
        } catch (e) {
            console.warn(
                "KeyStore: Failed to set key for",
                provider + ":",
                e
            );

            return false;
        }
    }

    function deleteKey(provider) {
        if (!provider)
            return false;

        if (!ensureDatabase())
            return false;

        try {
            database.transaction(function(tx) {
                tx.executeSql(
                    "DELETE FROM api_keys WHERE provider = ?",
                    [provider]
                );
            });

            refreshKeys();
            return true;
        } catch (e) {
            console.warn(
                "KeyStore: Failed to delete key for",
                provider + ":",
                e
            );

            return false;
        }
    }
}
