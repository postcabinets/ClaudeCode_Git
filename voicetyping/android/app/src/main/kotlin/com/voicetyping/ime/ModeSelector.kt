package com.voicetyping.ime

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.*
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.voicetyping.model.OutputMode

@Composable
fun ModeSelector(
    selectedMode: OutputMode,
    onModeSelected: (OutputMode) -> Unit,
) {
    Row(
        horizontalArrangement = Arrangement.spacedBy(6.dp),
        modifier = Modifier.padding(horizontal = 8.dp, vertical = 4.dp)
    ) {
        OutputMode.entries.forEach { mode ->
            FilterChip(
                selected = mode == selectedMode,
                onClick = { onModeSelected(mode) },
                label = { Text(mode.label, fontSize = 11.sp) },
                shape = RoundedCornerShape(8.dp),
                modifier = Modifier.height(28.dp),
            )
        }
    }
}
