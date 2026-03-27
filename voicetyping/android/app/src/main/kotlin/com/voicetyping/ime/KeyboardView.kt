package com.voicetyping.ime

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.voicetyping.model.OutputMode

@Composable
fun KeyboardLayout(
    transcription: String,
    cleanedText: String?,
    isRecording: Boolean,
    isProcessing: Boolean,
    selectedMode: OutputMode,
    onModeSelected: (OutputMode) -> Unit,
    onMicTap: () -> Unit,
    onInsert: () -> Unit,
    onBackspace: () -> Unit,
    onSpace: () -> Unit,
    onReturn: () -> Unit,
    onSwitchKeyboard: () -> Unit,
) {
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .height(240.dp)
            .background(MaterialTheme.colorScheme.surfaceVariant)
    ) {
        ModeSelector(selectedMode = selectedMode, onModeSelected = onModeSelected)

        if (transcription.isNotEmpty() || isProcessing) {
            Box(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(horizontal = 8.dp)
                    .clip(RoundedCornerShape(8.dp))
                    .background(MaterialTheme.colorScheme.surface)
                    .clickable { if (cleanedText != null) onInsert() }
                    .padding(8.dp)
            ) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Text(
                        text = cleanedText ?: transcription,
                        fontSize = 14.sp,
                        maxLines = 3,
                        overflow = TextOverflow.Ellipsis,
                        modifier = Modifier.weight(1f)
                    )
                    if (isProcessing) {
                        CircularProgressIndicator(
                            modifier = Modifier.size(16.dp),
                            strokeWidth = 2.dp
                        )
                    }
                }
            }
        }

        Spacer(modifier = Modifier.weight(1f))

        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 4.dp, vertical = 4.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            IconButton(onClick = onSwitchKeyboard) {
                Text("\uD83C\uDF10", fontSize = 20.sp)
            }

            Button(
                onClick = onSpace,
                modifier = Modifier
                    .weight(1f)
                    .height(44.dp),
                shape = RoundedCornerShape(6.dp),
                colors = ButtonDefaults.buttonColors(
                    containerColor = MaterialTheme.colorScheme.surface,
                    contentColor = MaterialTheme.colorScheme.onSurface
                )
            ) {
                Text("space")
            }

            IconButton(onClick = onBackspace) {
                Text("\u232B", fontSize = 20.sp)
            }

            Box(
                modifier = Modifier
                    .size(52.dp)
                    .clip(CircleShape)
                    .background(if (isRecording) Color.Red else MaterialTheme.colorScheme.primary)
                    .clickable { onMicTap() },
                contentAlignment = Alignment.Center
            ) {
                Text(
                    if (isRecording) "\uD83D\uDD34" else "\uD83C\uDFA4",
                    fontSize = 24.sp
                )
            }
        }

        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 8.dp, vertical = 4.dp),
            horizontalArrangement = Arrangement.End
        ) {
            Button(
                onClick = onReturn,
                shape = RoundedCornerShape(6.dp)
            ) {
                Text("return")
            }
        }
    }
}
