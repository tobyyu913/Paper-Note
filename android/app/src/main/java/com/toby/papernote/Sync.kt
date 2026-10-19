package com.toby.papernote

import android.content.Context
import android.os.Handler
import android.os.Looper
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Button
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.window.Dialog
import org.json.JSONObject
import java.io.IOException
import java.net.HttpURLConnection
import java.net.URL
import java.net.URLEncoder
import java.text.DateFormat
import java.util.Date

/** One notebook as the sync store sees it. */
data class SyncRow(val id: String, val updatedAt: Long, val deleted: Boolean, val data: Notebook?)

/**
 * Account + sync through Firebase (Google) via its REST APIs — no SDK:
 * Firebase Authentication (email/password) and Cloud Firestore. Documents
 * live at users/{uid}/notebooks/{id} with fields updatedAt, deleted and data
 * (the notebook as a JSON string). Network work runs on a background
 * thread; results land on the main thread.
 */
class SyncAccount(context: Context, private val store: NotebookStore) {
    private val prefs = context.getSharedPreferences("paper_note_sync", Context.MODE_PRIVATE)
    private val main = Handler(Looper.getMainLooper())

    var email by mutableStateOf(prefs.getString("email", "") ?: "")
        private set
    private var uid: String = prefs.getString("uid", "") ?: ""
    private var refreshToken: String = prefs.getString("refresh", "") ?: ""
    private var idToken = ""
    private var idTokenExpiry = 0L
    var isSignedIn by mutableStateOf(refreshToken.isNotEmpty() && uid.isNotEmpty())
        private set

    var status by mutableStateOf("")
    var lastSync by mutableStateOf<Long?>(null)
    var syncing by mutableStateOf(false)
        private set

    private fun persist() {
        prefs.edit().putString("email", email).putString("uid", uid).putString("refresh", refreshToken).apply()
        isSignedIn = refreshToken.isNotEmpty() && uid.isNotEmpty()
    }

    // ---- HTTP (call off the main thread) ----

    private class NotSignedIn : IOException("Not signed in")

    private fun request(url: String, method: String = "POST", body: JSONObject? = null, bearer: String? = null): JSONObject {
        val conn = URL(url).openConnection() as HttpURLConnection
        conn.requestMethod = method
        conn.connectTimeout = 15_000
        conn.readTimeout = 30_000
        conn.setRequestProperty("Content-Type", "application/json")
        if (bearer != null) conn.setRequestProperty("Authorization", "Bearer $bearer")
        if (body != null) {
            conn.doOutput = true
            conn.outputStream.use { it.write(body.toString().toByteArray()) }
        }
        val code = conn.responseCode
        val text = (if (code in 200..299) conn.inputStream else conn.errorStream)
            ?.bufferedReader()?.use { it.readText() } ?: ""
        conn.disconnect()
        val obj = runCatching { JSONObject(text) }.getOrDefault(JSONObject())
        if (code !in 200..299) {
            val msg = obj.optJSONObject("error")?.optString("message").orEmpty()
            throw IOException(if (msg.isEmpty()) "Server returned HTTP $code" else friendly(msg))
        }
        return obj
    }

    private fun friendly(code: String): String = when (code.substringBefore(' ')) {
        "EMAIL_EXISTS" -> "That email already has an account — sign in instead"
        "EMAIL_NOT_FOUND", "INVALID_PASSWORD", "INVALID_LOGIN_CREDENTIALS" -> "Wrong email or password"
        "INVALID_EMAIL" -> "Enter a valid email address"
        "WEAK_PASSWORD" -> "Password must be at least 6 characters"
        "TOO_MANY_ATTEMPTS_TRY_LATER" -> "Too many attempts — try again later"
        else -> code
    }

    /** A valid ID token, refreshed when about to expire. Background thread. */
    private fun freshToken(): String {
        if (refreshToken.isEmpty() || uid.isEmpty()) throw NotSignedIn()
        if (idToken.isNotEmpty() && idTokenExpiry > System.currentTimeMillis()) return idToken
        try {
            val r = request(
                "$TOKEN_URL?key=$API_KEY",
                body = JSONObject().put("grant_type", "refresh_token").put("refresh_token", refreshToken)
            )
            idToken = r.optString("id_token")
            r.optString("refresh_token").takeIf { it.isNotEmpty() }?.let { refreshToken = it }
            idTokenExpiry = System.currentTimeMillis() + 3_300_000L
            return idToken
        } catch (e: IOException) {
            val m = e.message.orEmpty()
            if ("TOKEN_EXPIRED" in m || "USER_NOT_FOUND" in m || "INVALID_REFRESH_TOKEN" in m) {
                main.post { signOut() }
                throw NotSignedIn()
            }
            throw e
        }
    }

    // ---- Public API (main thread) ----

    fun signIn(email: String, password: String, create: Boolean, done: (String?) -> Unit) {
        Thread {
            try {
                val r = request(
                    "$AUTH_URL:${if (create) "signUp" else "signInWithPassword"}?key=$API_KEY",
                    body = JSONObject().put("email", email).put("password", password).put("returnSecureToken", true)
                )
                main.post {
                    this.email = r.optString("email", email)
                    uid = r.optString("localId")
                    refreshToken = r.optString("refreshToken")
                    idToken = r.optString("idToken")
                    idTokenExpiry = System.currentTimeMillis() + 3_300_000L
                    persist()
                    status = "Signed in as ${this.email}"
                    done(null)
                    syncNow()
                }
            } catch (e: Exception) {
                main.post { done(e.message ?: "Sign-in failed") }
            }
        }.start()
    }

    fun signOut() {
        refreshToken = ""; uid = ""; idToken = ""
        persist()
        status = "Signed out"
        lastSync = null
    }

    private val syncRunnable = Runnable { syncNow() }

    /** Sync shortly after the last edit (edits come in bursts while typing). */
    fun scheduleSync(delayMs: Long = 2000) {
        if (!isSignedIn) return
        main.removeCallbacks(syncRunnable)
        main.postDelayed(syncRunnable, delayMs)
    }

    fun syncNow() {
        if (!isSignedIn || syncing) return
        syncing = true
        val local = store.notebooks.map { SyncRow(it.id.lowercase(), it.updatedAt, false, it) } +
            store.tombstones.map { (id, at) -> SyncRow(id, at, true, null) }

        Thread {
            try {
                val token = freshToken()
                val collection = "$FIRESTORE_URL/users/$uid/notebooks"

                // 1. Everything the store has for this user.
                val remote = HashMap<String, SyncRow>()
                var pageToken: String? = null
                do {
                    var url = "$collection?pageSize=300"
                    if (pageToken != null) url += "&pageToken=" + URLEncoder.encode(pageToken, "UTF-8")
                    val r = request(url, method = "GET", bearer = token)
                    val docs = r.optJSONArray("documents")
                    if (docs != null) for (i in 0 until docs.length()) {
                        rowFrom(docs.getJSONObject(i))?.let { remote[it.id] = it }
                    }
                    pageToken = r.optString("nextPageToken").takeIf { it.isNotEmpty() }
                } while (pageToken != null)

                // 2. Push whatever is newer here.
                val merged = HashMap(remote)
                for (row in local) {
                    val theirs = remote[row.id]?.updatedAt ?: -1L
                    if (row.updatedAt <= theirs) continue
                    request("$collection/${row.id}", method = "PATCH", body = documentFor(row), bearer = token)
                    merged[row.id] = row
                }

                main.post {
                    store.applyRemote(merged.values.toList())
                    store.tombstones.clear()
                    store.saveTombstones()
                    lastSync = System.currentTimeMillis()
                    status = "Synced"
                    syncing = false
                }
            } catch (e: Exception) {
                main.post {
                    status = if (e is NotSignedIn) "Signed out — please sign in again" else "Sync failed: ${e.message}"
                    syncing = false
                }
            }
        }.start()
    }

    // ---- Firestore document <-> row ----

    private fun documentFor(row: SyncRow): JSONObject {
        val fields = JSONObject()
            .put("updatedAt", JSONObject().put("integerValue", row.updatedAt.toString()))
            .put("deleted", JSONObject().put("booleanValue", row.deleted))
            .put("data", JSONObject().put("stringValue", row.data?.toJson()?.toString() ?: ""))
        return JSONObject().put("fields", fields)
    }

    private fun rowFrom(doc: JSONObject): SyncRow? {
        val name = doc.optString("name"); val fields = doc.optJSONObject("fields") ?: return null
        if (name.isEmpty()) return null
        val id = name.substringAfterLast('/').lowercase()
        val updatedAt = fields.optJSONObject("updatedAt")?.optString("integerValue")?.toLongOrNull() ?: 0L
        val deleted = fields.optJSONObject("deleted")?.optBoolean("booleanValue") ?: false
        val json = fields.optJSONObject("data")?.optString("stringValue").orEmpty()
        val nb = if (!deleted && json.isNotEmpty()) runCatching { Notebook.fromJson(JSONObject(json)) }.getOrNull() else null
        return SyncRow(id, updatedAt, deleted, nb)
    }

    companion object {
        private const val API_KEY = "AIzaSyCt7U0F5HRbL55B9B00L70lkzoksar4dTo"
        private const val PROJECT_ID = "paper-note-73a4d"
        private const val AUTH_URL = "https://identitytoolkit.googleapis.com/v1/accounts"
        private const val TOKEN_URL = "https://securetoken.googleapis.com/v1/token"
        private const val FIRESTORE_URL = "https://firestore.googleapis.com/v1/projects/$PROJECT_ID/databases/(default)/documents"
    }
}

@Composable
fun AccountDialog(store: NotebookStore, onDismiss: () -> Unit) {
    val sync = store.sync
    var email by remember { mutableStateOf(sync.email) }
    var password by remember { mutableStateOf("") }
    var error by remember { mutableStateOf<String?>(null) }
    var busy by remember { mutableStateOf(false) }

    fun submit(create: Boolean) {
        error = null; busy = true
        sync.signIn(email.trim(), password, create) { err ->
            busy = false
            if (err != null) error = err else password = ""
        }
    }

    Dialog(onDismissRequest = onDismiss) {
        Column(
            Modifier
                .background(Color(0xFF2A2018), RoundedCornerShape(16.dp))
                .padding(22.dp)
                .width(320.dp)
        ) {
            Text("Account", color = Color.White, fontSize = 18.sp)
            Spacer(Modifier.height(6.dp))
            Text(
                "Sign in with the same email on each device and your notebooks stay in sync through Google Firebase.",
                color = Color.White.copy(alpha = 0.55f), fontSize = 12.sp
            )
            Spacer(Modifier.height(16.dp))

            if (sync.isSignedIn) {
                Text("Signed in as ${sync.email}", color = Color.White.copy(alpha = 0.9f), fontSize = 14.sp)
                val last = sync.lastSync?.let { DateFormat.getTimeInstance(DateFormat.SHORT).format(Date(it)) } ?: "not yet"
                Text("Last sync: $last", color = Color.White.copy(alpha = 0.55f), fontSize = 12.sp)
                if (sync.status.isNotEmpty()) {
                    Spacer(Modifier.height(6.dp))
                    Text(sync.status, color = Color.White.copy(alpha = 0.7f), fontSize = 12.sp)
                }
                Spacer(Modifier.height(16.dp))
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Button(onClick = { sync.syncNow() }, enabled = !sync.syncing) {
                        Text(if (sync.syncing) "Syncing…" else "Sync now")
                    }
                    Spacer(Modifier.width(8.dp))
                    TextButton(onClick = { sync.signOut() }) { Text("Sign out", color = Color(0xFFE57373)) }
                    Spacer(Modifier.weight(1f))
                    TextButton(onClick = onDismiss) { Text("Done") }
                }
            } else {
                OutlinedTextField(
                    value = email, onValueChange = { email = it; error = null },
                    label = { Text("Email") }, singleLine = true, modifier = Modifier.fillMaxWidth()
                )
                Spacer(Modifier.height(8.dp))
                OutlinedTextField(
                    value = password, onValueChange = { password = it; error = null },
                    label = { Text("Password") }, singleLine = true,
                    visualTransformation = PasswordVisualTransformation(),
                    modifier = Modifier.fillMaxWidth()
                )
                if (error != null) {
                    Spacer(Modifier.height(8.dp))
                    Text(error!!, color = Color(0xFFE57373), fontSize = 12.sp)
                }
                Spacer(Modifier.height(16.dp))
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Button(onClick = { submit(false) }, enabled = !busy) { Text("Sign in") }
                    Spacer(Modifier.width(8.dp))
                    TextButton(onClick = { submit(true) }, enabled = !busy) { Text("Create account") }
                    Spacer(Modifier.weight(1f))
                    TextButton(onClick = onDismiss) { Text("Cancel") }
                }
            }
        }
    }
}
