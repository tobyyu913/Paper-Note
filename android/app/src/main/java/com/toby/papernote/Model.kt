package com.toby.papernote

import android.content.Context
import androidx.compose.runtime.Stable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.setValue
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.time.LocalDate
import java.time.format.DateTimeFormatter
import java.util.UUID

data class Notebook(
    val id: String = UUID.randomUUID().toString(),
    val title: String = "Untitled",
    val writer: String = "",
    val dateText: String = "",
    val leather: Int = 0,
    val pages: List<String> = listOf(""),
    /** Milliseconds since 1970 of the last edit; used to merge across devices. */
    val updatedAt: Long = 0L,
    /** List marks made on macOS, carried through untouched so syncing from a phone never drops them. */
    val pageMarks: JSONArray? = null
) {
    val pageCount: Int get() = maxOf(1, pages.size)
    val palette: Leather get() = leathers[leather.coerceIn(0, leathers.size - 1)]

    fun toJson(): JSONObject = JSONObject().apply {
        put("id", id)
        put("title", title)
        put("writer", writer)
        put("dateText", dateText)
        put("leather", leather)
        put("pages", JSONArray(pages))
        if (updatedAt > 0L) put("updatedAt", updatedAt)
        if (pageMarks != null) put("pageMarks", pageMarks)
    }

    companion object {
        fun fromJson(o: JSONObject): Notebook {
            val arr = o.optJSONArray("pages") ?: JSONArray().put("")
            val pages = (0 until arr.length()).map { arr.getString(it) }
            return Notebook(
                id = o.optString("id", UUID.randomUUID().toString()),
                title = o.optString("title", "Untitled"),
                writer = o.optString("writer", ""),
                dateText = o.optString("dateText", ""),
                leather = o.optInt("leather", 0),
                pages = pages.ifEmpty { listOf("") },
                updatedAt = o.optLong("updatedAt", 0L),
                pageMarks = o.optJSONArray("pageMarks")
            )
        }
    }
}

@Stable
class NotebookStore(context: Context) {
    val notebooks = mutableStateListOf<Notebook>()
    var openIndex by mutableStateOf<Int?>(null)

    private val file = File(context.filesDir, "library.json")
    private val prefs = context.getSharedPreferences("paper_note", Context.MODE_PRIVATE)

    /** The passcode that unlocks notebooks when fingerprint is off/unavailable. */
    var passcode by mutableStateOf(prefs.getString(KEY_PASSCODE, DEFAULT_PASSCODE) ?: DEFAULT_PASSCODE)
        private set

    /** Whether a fingerprint may be used to unlock notebooks. Defaults to on. */
    var useBiometrics by mutableStateOf(prefs.getBoolean(KEY_USE_BIOMETRICS, true))
        private set

    fun updatePasscode(value: String) {
        passcode = value
        prefs.edit().putString(KEY_PASSCODE, value).apply()
    }

    fun updateUseBiometrics(value: Boolean) {
        useBiometrics = value
        prefs.edit().putBoolean(KEY_USE_BIOMETRICS, value).apply()
    }

    val sync = SyncAccount(context, this)

    init { load() }

    fun newNotebook(): Int {
        val date = LocalDate.now().format(DateTimeFormatter.ofPattern("MMMM d, yyyy"))
        notebooks.add(
            Notebook(
                dateText = date,
                leather = notebooks.size % leathers.size,
                updatedAt = System.currentTimeMillis()
            )
        )
        save()
        return notebooks.size - 1
    }

    fun update(index: Int, transform: (Notebook) -> Notebook) {
        if (index in notebooks.indices) {
            val before = notebooks[index]
            val after = transform(before)
            if (after == before) return
            notebooks[index] = after.copy(updatedAt = System.currentTimeMillis())
            save()
        }
    }

    fun delete(index: Int) {
        if (index in notebooks.indices) {
            val id = notebooks[index].id.lowercase()
            tombstones[id] = System.currentTimeMillis()
            saveTombstones()
            notebooks.removeAt(index)
            save()
        }
    }

    // ---- Sync support ----

    /** Deleted notebook ids → when, so deletions reach other devices. */
    val tombstones: MutableMap<String, Long> = loadTombstones()

    private fun loadTombstones(): MutableMap<String, Long> {
        val m = mutableMapOf<String, Long>()
        runCatching {
            val o = JSONObject(prefs.getString(KEY_TOMBSTONES, "{}") ?: "{}")
            o.keys().forEach { k -> m[k] = o.getLong(k) }
        }
        return m
    }

    fun saveTombstones() {
        val o = JSONObject()
        tombstones.forEach { (k, v) -> o.put(k, v) }
        prefs.edit().putString(KEY_TOMBSTONES, o.toString()).apply()
    }

    /**
     * Merges the server's set in: newer wins per notebook, deletions remove
     * local copies that aren't newer. Must run on the main thread.
     */
    fun applyRemote(rows: List<SyncRow>) {
        var changed = false
        for (row in rows) {
            val i = notebooks.indexOfFirst { it.id.equals(row.id, ignoreCase = true) }
            val localStamp = if (i >= 0) notebooks[i].updatedAt else -1L
            if (row.deleted) {
                if (i >= 0 && localStamp <= row.updatedAt) {
                    if (openIndex == i) openIndex = null
                    notebooks.removeAt(i); changed = true
                }
            } else if (row.data != null) {
                val nb = row.data.copy(id = row.id.lowercase(), updatedAt = row.updatedAt)
                if (i >= 0) {
                    if (row.updatedAt > localStamp) { notebooks[i] = nb; changed = true }
                } else if (!tombstones.containsKey(row.id.lowercase())) {
                    notebooks.add(nb); changed = true
                }
            }
        }
        if (changed) save(triggerSync = false)
    }

    private fun load() {
        if (!file.exists()) return
        runCatching {
            val arr = JSONArray(file.readText())
            notebooks.clear()
            for (i in 0 until arr.length()) {
                notebooks.add(Notebook.fromJson(arr.getJSONObject(i)))
            }
        }
    }

    fun save(triggerSync: Boolean = true) {
        runCatching {
            val arr = JSONArray()
            notebooks.forEach { arr.put(it.toJson()) }
            file.writeText(arr.toString())
        }
        if (triggerSync) sync.scheduleSync()
    }

    companion object {
        const val DEFAULT_PASSCODE = "paper note"
        private const val KEY_PASSCODE = "passcode"
        private const val KEY_USE_BIOMETRICS = "use_biometrics"
        private const val KEY_TOMBSTONES = "tombstones"
    }
}
