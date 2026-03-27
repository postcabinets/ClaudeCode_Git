package com.voicetyping

import android.content.Intent
import android.os.Bundle
import android.provider.Settings as AndroidSettings
import android.view.inputmethod.InputMethodManager
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.voicetyping.model.OutputMode
import com.voicetyping.model.Settings

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContent {
            MaterialTheme {
                MainScreen()
            }
        }
    }
}

@Composable
fun MainScreen() {
    val context = LocalContext.current
    val settings = remember { Settings(context) }
    var selectedMode by remember { mutableStateOf(settings.selectedMode) }

    Column(
        modifier = Modifier
            .fillMaxSize()
            .padding(24.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Text("VoiceTyping", fontSize = 28.sp, fontWeight = FontWeight.Bold)
        Spacer(modifier = Modifier.height(32.dp))

        Text("セットアップ", fontSize = 18.sp, fontWeight = FontWeight.SemiBold)
        Spacer(modifier = Modifier.height(12.dp))

        OutlinedCard(modifier = Modifier.fillMaxWidth()) {
            Column(modifier = Modifier.padding(16.dp)) {
                Text("1. 「キーボードを有効にする」をタップ", fontSize = 14.sp)
                Text("2. VoiceTyping をONにする", fontSize = 14.sp)
                Text("3. テキスト入力時にキーボード切替", fontSize = 14.sp)
            }
        }

        Spacer(modifier = Modifier.height(12.dp))

        Button(
            onClick = {
                context.startActivity(Intent(AndroidSettings.ACTION_INPUT_METHOD_SETTINGS))
            },
            modifier = Modifier.fillMaxWidth(),
            shape = RoundedCornerShape(12.dp)
        ) {
            Text("キーボードを有効にする")
        }

        Spacer(modifier = Modifier.height(8.dp))

        OutlinedButton(
            onClick = {
                val imm = context.getSystemService(InputMethodManager::class.java)
                imm.showInputMethodPicker()
            },
            modifier = Modifier.fillMaxWidth(),
            shape = RoundedCornerShape(12.dp)
        ) {
            Text("キーボードを切り替える")
        }

        Spacer(modifier = Modifier.height(32.dp))

        Text("デフォルトモード", fontSize = 18.sp, fontWeight = FontWeight.SemiBold)
        Spacer(modifier = Modifier.height(12.dp))

        OutputMode.entries.forEach { mode ->
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(vertical = 4.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                RadioButton(
                    selected = mode == selectedMode,
                    onClick = {
                        selectedMode = mode
                        settings.selectedMode = mode
                    }
                )
                Spacer(modifier = Modifier.width(8.dp))
                Text(mode.label, fontSize = 16.sp)
            }
        }

        Spacer(modifier = Modifier.weight(1f))
        Text("VoiceTyping v1.0.0", fontSize = 12.sp, color = MaterialTheme.colorScheme.onSurfaceVariant)
    }
}
