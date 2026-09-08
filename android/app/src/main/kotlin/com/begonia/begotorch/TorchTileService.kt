package com.begonia.begotorch

import android.content.Context
import android.graphics.drawable.Icon
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.service.quicksettings.Tile
import android.service.quicksettings.TileService
import java.io.File
import java.util.concurrent.TimeUnit

/**
 * Quick Settings tile that toggles the torch between off (0) and full (7)
 * brightness by writing to the same sysfs node as the app:
 *
 *     echo "N" > /sys/devices/platform/flashlights_mt6360/torchbrightness
 *
 * The `su` binary is resolved with the same probe order as lib/main.dart
 * (kSuCandidates). Writes run on a worker thread; the tile never blocks the
 * main thread on a root call.
 */
class TorchTileService : TileService() {

    private val mainHandler = Handler(Looper.getMainLooper())

    override fun onStartListening() {
        super.onStartListening()
        runAsync {
            // Refresh state from the device (or last known level) so the tile
            // reflects changes made by the app between panel opens.
            queryLevel()
        }
    }

    override fun onClick() {
        // Main thread: decide from the cheap cached level only — never probe
        // su here. The worker thread verifies and corrects below.
        val assumed = lastLevel()
        val target = if (assumed == 0) ON_VALUE else OFF_VALUE

        // Optimistic update so the tile feels instant; corrected after the
        // write completes (or fails).
        updateTile(target)

        runAsync {
            val su = resolveSuPath() ?: return@runAsync queryLevel()
            val ok = writeTorch(su, target)
            if (ok) {
                rememberLevel(target)
            }
            if (ok) target else queryLevel()
        }
    }

    // --- state ---------------------------------------------------------------

    /** Best-effort current brightness: real sysfs value, else last known. */
    private fun queryLevel(): Int {
        val su = resolveSuPath()
        if (su != null) {
            val result = runCatching {
                exec(su, listOf("-c", "cat \"$TORCH_DEVICE\""))
            }.getOrNull()
            if (result != null && result.success) {
                val level = result.output.trim().toIntOrNull()
                if (level != null && level in MIN_VALUE..MAX_VALUE) {
                    return level
                }
            }
        }
        try {
            val level = File(TORCH_DEVICE).readText().trim().toIntOrNull()
            if (level != null && level in MIN_VALUE..MAX_VALUE) {
                return level
            }
        } catch (_: Exception) {
            // Node not readable by the app — fall through to the cached level.
        }
        return lastLevel()
    }

    private fun lastLevel(): Int =
        getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .getInt(KEY_LEVEL, OFF_VALUE)

    private fun rememberLevel(level: Int) {
        getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .edit()
            .putInt(KEY_LEVEL, level)
            .apply()
    }

    // --- su plumbing (mirrors lib/main.dart) ---------------------------------

    private data class ExecResult(
        val exitCode: Int,
        val output: String,
    ) {
        val success: Boolean get() = exitCode == 0
    }

    private fun exec(command: String, args: List<String>): ExecResult {
        val process = ProcessBuilder(listOf(command) + args)
            .redirectErrorStream(true)
            .start()
        val output = process.inputStream.bufferedReader().use { it.readText() }
        if (!process.waitFor(3, TimeUnit.SECONDS)) {
            process.destroyForcibly()
            return ExecResult(exitCode = -1, output = "")
        }
        return ExecResult(exitCode = process.exitValue(), output = output)
    }

    /** First working `su` path, cached for the life of the process. */
    private fun resolveSuPath(): String? {
        suPathCache?.let { return it.ifEmpty { null } }
        for (candidate in SU_CANDIDATES) {
            val result = runCatching {
                exec(candidate, listOf("--version"))
            }.getOrNull() ?: continue
            if (result.exitCode != 127) {
                suPathCache = candidate
                return candidate
            }
        }
        suPathCache = ""
        return null
    }

    private fun writeTorch(su: String, level: Int): Boolean {
        val result = runCatching {
            exec(su, listOf("-c", "echo \"$level\" > \"$TORCH_DEVICE\""))
        }.getOrNull() ?: return false
        return result.success
    }

    // --- tile rendering ------------------------------------------------------

    private fun updateTile(level: Int) {
        val tile = qsTile ?: return
        tile.state = if (level == 0) Tile.STATE_INACTIVE else Tile.STATE_ACTIVE
        tile.label = getString(R.string.tile_label)
        tile.icon = Icon.createWithResource(this, R.drawable.ic_tile_torch)
        if (level > 0) {
            val description = getString(R.string.tile_state_level, level)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                tile.subtitle = description
            }
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                tile.stateDescription = description
            }
        }
        tile.updateTile()
    }

    private fun runAsync(block: () -> Int) {
        Thread {
            val level = try {
                block()
            } catch (_: Exception) {
                lastLevel()
            }
            mainHandler.post { updateTile(level) }
        }.start()
    }

    private companion object {
        const val PREFS = "begotorch_tile"
        const val KEY_LEVEL = "last_level"

        const val TORCH_DEVICE =
            "/sys/devices/platform/flashlights_mt6360/torchbrightness"

        const val MIN_VALUE = 0
        const val MAX_VALUE = 7
        const val OFF_VALUE = MIN_VALUE
        const val ON_VALUE = MAX_VALUE

        // Same probe order as kSuCandidates in lib/main.dart.
        val SU_CANDIDATES = listOf(
            "/system/bin/su",
            "/system/xbin/su",
            "/su/bin/su",
            "/data/adb/ap/bin/su",
            "/sbin/su",
            "/magisk/.core/bin/su",
        )

        /** Resolved su path; empty string means "none found" (negative cache). */
        @Volatile
        var suPathCache: String? = null
    }
}
