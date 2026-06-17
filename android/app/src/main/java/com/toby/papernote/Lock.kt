package com.toby.papernote

import android.content.Context
import androidx.biometric.BiometricManager
import androidx.biometric.BiometricPrompt
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Fingerprint
import androidx.compose.material.icons.filled.Lock
import androidx.compose.material3.Button
import androidx.compose.material3.Icon
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.window.Dialog
import androidx.core.content.ContextCompat
import androidx.fragment.app.FragmentActivity

/** True when this device has an enrolled fingerprint/biometric that can be used. */
fun biometricAvailable(context: Context): Boolean =
    BiometricManager.from(context)
        .canAuthenticate(BiometricManager.Authenticators.BIOMETRIC_WEAK) ==
            BiometricManager.BIOMETRIC_SUCCESS

/** Shows the system fingerprint prompt. Calls [onSuccess] when it succeeds. */
fun promptBiometric(
    activity: FragmentActivity,
    subtitle: String,
    onSuccess: () -> Unit
) {
    val prompt = BiometricPrompt(
        activity,
        ContextCompat.getMainExecutor(activity),
        object : BiometricPrompt.AuthenticationCallback() {
            override fun onAuthenticationSucceeded(result: BiometricPrompt.AuthenticationResult) {
                onSuccess()
            }
        }
    )
    val info = BiometricPrompt.PromptInfo.Builder()
        .setTitle("Unlock notebook")
        .setSubtitle(subtitle)
        .setNegativeButtonText("Use passcode")
        .setAllowedAuthenticators(BiometricManager.Authenticators.BIOMETRIC_WEAK)
        .build()
    prompt.authenticate(info)
}

/**
 * Gate shown before a notebook opens. Tries fingerprint first (when enabled and
 * available); the owner can type the passcode instead ("paper note" by default).
 */
@Composable
fun UnlockScreen(
    store: NotebookStore,
    title: String,
    onUnlock: () -> Unit,
    onCancel: () -> Unit
) {
    val context = LocalContext.current
    val activity = context as? FragmentActivity
    val bookName = if (title.isBlank()) "this notebook" else "“$title”"
    val canUseFingerprint = store.useBiometrics && biometricAvailable(context) && activity != null

    var entry by remember { mutableStateOf("") }
    var wrong by remember { mutableStateOf(false) }

    fun submit() {
        if (entry == store.passcode) onUnlock()
        else { wrong = true; entry = "" }
    }

    LaunchedEffect(Unit) {
        if (canUseFingerprint && activity != null) {
            promptBiometric(activity, "Unlock $bookName", onUnlock)
        }
    }

    Column(
        Modifier
            .fillMaxSize()
            .background(
                Brush.verticalGradient(
                    listOf(Color(0xFF2E2117), Color(0xFF1A130D))
                )
            )
            .imePadding()
            .padding(40.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.Center
    ) {
        Icon(
            Icons.Filled.Lock, "Locked",
            tint = Color.White.copy(alpha = 0.85f),
            modifier = Modifier.size(44.dp)
        )
        Spacer(Modifier.height(18.dp))
        Text(
            "Locked",
            color = Color.White.copy(alpha = 0.92f),
            fontFamily = Handwriting,
            fontSize = 30.sp
        )
        Spacer(Modifier.height(10.dp))
        Text(
            if (canUseFingerprint) "Unlock $bookName with your fingerprint or passcode."
            else "Unlock $bookName with your passcode.",
            color = Color.White.copy(alpha = 0.6f),
            fontSize = 13.sp,
            modifier = Modifier.fillMaxWidth(),
            textAlign = androidx.compose.ui.text.style.TextAlign.Center
        )
        Spacer(Modifier.height(22.dp))

        OutlinedTextField(
            value = entry,
            onValueChange = { entry = it; wrong = false },
            label = { Text("Passcode") },
            singleLine = true,
            visualTransformation = PasswordVisualTransformation(),
            modifier = Modifier.width(260.dp)
        )
        if (wrong) {
            Spacer(Modifier.height(6.dp))
            Text("Incorrect passcode", color = Color(0xFFE57373), fontSize = 12.sp)
        }
        Spacer(Modifier.height(12.dp))
        Button(onClick = ::submit, enabled = entry.isNotEmpty(), modifier = Modifier.width(260.dp)) {
            Text("Unlock")
        }

        if (canUseFingerprint && activity != null) {
            Spacer(Modifier.height(4.dp))
            TextButton(onClick = { promptBiometric(activity, "Unlock $bookName", onUnlock) }) {
                Icon(Icons.Filled.Fingerprint, null, tint = Color.White.copy(alpha = 0.8f))
                Spacer(Modifier.width(6.dp))
                Text("Use fingerprint", color = Color.White.copy(alpha = 0.8f))
            }
        }

        Spacer(Modifier.height(16.dp))
        TextButton(onClick = onCancel) {
            Text("Back to Shelf", color = Color.White.copy(alpha = 0.5f), fontSize = 12.sp)
        }
    }
}

/** Lets the owner toggle fingerprint unlock and change the passcode. */
@Composable
fun SecurityDialog(store: NotebookStore, onDismiss: () -> Unit) {
    val context = LocalContext.current
    val hasFingerprint = biometricAvailable(context)

    var current by remember { mutableStateOf("") }
    var newPass by remember { mutableStateOf("") }
    var confirm by remember { mutableStateOf("") }
    var error by remember { mutableStateOf<String?>(null) }
    var saved by remember { mutableStateOf(false) }

    fun savePasscode() {
        when {
            current != store.passcode -> error = "Current passcode is incorrect"
            newPass.isEmpty() -> error = "Enter a new passcode"
            newPass != confirm -> error = "Passcodes don’t match"
            else -> {
                store.updatePasscode(newPass)
                error = null; saved = true
                current = ""; newPass = ""; confirm = ""
            }
        }
    }

    Dialog(onDismissRequest = onDismiss) {
        Column(
            Modifier
                .background(Color(0xFF2A2018), androidx.compose.foundation.shape.RoundedCornerShape(16.dp))
                .padding(22.dp)
                .width(320.dp)
        ) {
            Text("Security", color = Color.White, fontSize = 18.sp)
            Spacer(Modifier.height(16.dp))

            if (hasFingerprint) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Column(Modifier.weight(1f)) {
                        Text("Unlock with fingerprint", color = Color.White.copy(alpha = 0.9f), fontSize = 14.sp)
                        Text(
                            "When off, notebooks open with the passcode only.",
                            color = Color.White.copy(alpha = 0.55f), fontSize = 11.sp
                        )
                    }
                    Switch(checked = store.useBiometrics, onCheckedChange = { store.updateUseBiometrics(it) })
                }
                Spacer(Modifier.height(16.dp))
            }

            Text("Change passcode", color = Color.White.copy(alpha = 0.9f), fontSize = 14.sp)
            Spacer(Modifier.height(8.dp))
            OutlinedTextField(
                value = current, onValueChange = { current = it; error = null; saved = false },
                label = { Text("Current passcode") }, singleLine = true,
                visualTransformation = PasswordVisualTransformation(),
                modifier = Modifier.fillMaxWidth()
            )
            Spacer(Modifier.height(8.dp))
            OutlinedTextField(
                value = newPass, onValueChange = { newPass = it; error = null; saved = false },
                label = { Text("New passcode") }, singleLine = true,
                visualTransformation = PasswordVisualTransformation(),
                modifier = Modifier.fillMaxWidth()
            )
            Spacer(Modifier.height(8.dp))
            OutlinedTextField(
                value = confirm, onValueChange = { confirm = it; error = null; saved = false },
                label = { Text("Confirm new passcode") }, singleLine = true,
                visualTransformation = PasswordVisualTransformation(),
                modifier = Modifier.fillMaxWidth()
            )

            error?.let {
                Spacer(Modifier.height(8.dp))
                Text(it, color = Color(0xFFE57373), fontSize = 12.sp)
            }
            if (saved) {
                Spacer(Modifier.height(8.dp))
                Text("Passcode updated", color = Color(0xFF81C784), fontSize = 12.sp)
            }

            Spacer(Modifier.height(16.dp))
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.End) {
                TextButton(onClick = onDismiss) { Text("Done") }
                Spacer(Modifier.width(8.dp))
                OutlinedButton(onClick = ::savePasscode) { Text("Save") }
            }
        }
    }
}
