package com.toby.papernote

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.text.BasicText
import androidx.compose.runtime.remember
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.PathEffect
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp

@Composable
fun CoverView(
    notebook: Notebook,
    onUpdate: (Notebook) -> Unit,
    onOpenStud: () -> Unit,
    modifier: Modifier = Modifier
) {
    val p = notebook.palette
    Box(modifier) {
        // Leather surface + stitched border.
        Canvas(Modifier.fillMaxSize()) {
            val w = size.width
            val h = size.height
            drawRect(
                Brush.linearGradient(
                    listOf(p.high, p.base, p.base.copy(alpha = 0.9f)),
                    start = Offset(0f, 0f), end = Offset(w, h)
                )
            )
            // Grain.
            var seed = 0x51EDL
            fun rnd(): Float {
                seed = seed * 6364136223846793005L + 1442695040888963407L
                return ((seed ushr 33).toDouble() / Int.MAX_VALUE).toFloat()
            }
            repeat(900) {
                val x = rnd() * w
                val y = rnd() * h
                val len = 2f + rnd() * 6f
                val bright = rnd() > 0.5f
                drawLine(
                    if (bright) Color.White.copy(alpha = 0.04f) else Color.Black.copy(alpha = 0.06f),
                    Offset(x, y), Offset(x + len, y + (rnd() - 0.5f) * 2f), strokeWidth = 0.8f
                )
            }
            // Edge shading.
            drawRect(
                Brush.radialGradient(
                    listOf(Color.Transparent, Color.Black.copy(alpha = 0.28f)),
                    center = Offset(w / 2, h / 2), radius = maxOf(w, h) * 0.72f
                )
            )
            // Stitched border.
            val inset = 22.dp.toPx()
            drawRoundRect(
                color = p.stitch.copy(alpha = 0.8f),
                topLeft = Offset(inset, inset),
                size = androidx.compose.ui.geometry.Size(w - inset * 2, h - inset * 2),
                cornerRadius = androidx.compose.ui.geometry.CornerRadius(10.dp.toPx()),
                style = Stroke(
                    width = 1.6.dp.toPx(),
                    pathEffect = PathEffect.dashPathEffect(
                        floatArrayOf(8.dp.toPx(), 6.dp.toPx())
                    )
                )
            )
        }

        // Title / writer / date.
        Column(
            Modifier.fillMaxSize().padding(horizontal = 36.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.Center
        ) {
            engravedField(notebook.title, "Title", 34.sp, FontWeight.Bold) {
                onUpdate(notebook.copy(title = it))
            }
            Box(
                Modifier.padding(vertical = 14.dp).size(width = 120.dp, height = 1.dp)
                    .background(p.stitch.copy(alpha = 0.5f))
            )
            engravedField(notebook.writer, "Writer", 18.sp, FontWeight.Normal) {
                onUpdate(notebook.copy(writer = it))
            }
            engravedField(notebook.dateText, "Date", 15.sp, FontWeight.Normal) {
                onUpdate(notebook.copy(dateText = it))
            }
        }

        // Press stud on the right edge.
        Box(
            Modifier.align(Alignment.CenterEnd).padding(end = 2.dp),
            contentAlignment = Alignment.Center
        ) {
            Box(
                Modifier
                    .size(34.dp)
                    .clickable(
                        interactionSource = remember { MutableInteractionSource() },
                        indication = null
                    ) { onOpenStud() }
            ) {
                Canvas(Modifier.fillMaxSize()) {
                    val c = Offset(size.width / 2, size.height / 2)
                    // strap
                    drawRoundRect(
                        Brush.verticalGradient(listOf(p.stitch.copy(alpha = 0.5f), Color.Black.copy(alpha = 0.4f))),
                        topLeft = Offset(c.x - 9.dp.toPx(), c.y - 26.dp.toPx()),
                        size = androidx.compose.ui.geometry.Size(18.dp.toPx(), 52.dp.toPx()),
                        cornerRadius = androidx.compose.ui.geometry.CornerRadius(9.dp.toPx())
                    )
                    // metal stud
                    drawCircle(
                        Brush.radialGradient(
                            listOf(Color(0xFFF2F2F2), Color(0xFFA6A6A6), Color(0xFF595959)),
                            center = Offset(c.x - 3.dp.toPx(), c.y - 3.dp.toPx()),
                            radius = 14.dp.toPx()
                        ),
                        radius = 11.dp.toPx(), center = c
                    )
                    drawCircle(Color.White.copy(alpha = 0.5f), radius = 2.dp.toPx(),
                        center = Offset(c.x - 3.dp.toPx(), c.y - 3.dp.toPx()))
                }
            }
        }
    }
}

@Composable
private fun engravedField(
    value: String,
    placeholder: String,
    size: androidx.compose.ui.unit.TextUnit,
    weight: FontWeight,
    onChange: (String) -> Unit
) {
    val textStyle = TextStyle(
        color = Color.White.copy(alpha = 0.92f),
        fontFamily = Handwriting, fontSize = size, fontWeight = weight,
        textAlign = TextAlign.Center
    )
    BasicTextField(
        value = value,
        onValueChange = onChange,
        textStyle = textStyle,
        cursorBrush = SolidColor(Color.White),
        modifier = Modifier.fillMaxWidth(),
        decorationBox = { inner ->
            Box(contentAlignment = Alignment.Center) {
                if (value.isEmpty()) {
                    BasicText(placeholder, style = textStyle.copy(color = Color.White.copy(alpha = 0.3f)))
                }
                inner()
            }
        }
    )
}
