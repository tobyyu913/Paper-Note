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
    val pages: List<String> = listOf("")
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
                pages = pages.ifEmpty { listOf("") }
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

    init { load() }

    fun newNotebook(): Int {
        val date = LocalDate.now().format(DateTimeFormatter.ofPattern("MMMM d, yyyy"))
        notebooks.add(
            Notebook(
                dateText = date,
                leather = notebooks.size % leathers.size
            )
        )
        save()
        return notebooks.size - 1
    }

    fun update(index: Int, transform: (Notebook) -> Notebook) {
        if (index in notebooks.indices) {
            notebooks[index] = transform(notebooks[index])
            save()
        }
    }

    fun delete(index: Int) {
        if (index in notebooks.indices) {
            notebooks.removeAt(index)
            save()
        }
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

    fun save() {
        runCatching {
            val arr = JSONArray()
            notebooks.forEach { arr.put(it.toJson()) }
            file.writeText(arr.toString())
        }
    }

    companion object {
        const val DEFAULT_PASSCODE = "paper note"
        private const val KEY_PASSCODE = "passcode"
        private const val KEY_USE_BIOMETRICS = "use_biometrics"
    }
}
