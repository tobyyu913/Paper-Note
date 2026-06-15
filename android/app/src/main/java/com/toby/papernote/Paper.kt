package com.toby.papernote

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.text.TextLayoutResult
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.input.TextFieldValue
import androidx.compose.ui.text.TextRange
import androidx.compose.ui.text.style.LineHeightStyle
import androidx.compose.ui.unit.dp

/**
 * One notebook page: warm ruled paper with the rules drawn at the exact text
 * baselines, so letters sit on the line and descenders dip below. Tapping
 * empty space places the cursor there, padding with blank lines/spaces.
 */
@Composable
fun PageSurface(
    pageKey: Int,
    initialText: String,
    editable: Boolean,
    onTextChange: (String) -> Unit,
    modifier: Modifier = Modifier
) {
    var tfv by remember(pageKey) {
        mutableStateOf(TextFieldValue(initialText, TextRange(initialText.length)))
    }
    var layout by remember(pageKey) { mutableStateOf<TextLayoutResult?>(null) }

    val style = TextStyle(
        color = Paper.ink,
        fontFamily = Handwriting,
        fontSize = Paper.fontSize,
        lineHeight = Paper.lineHeight,
        lineHeightStyle = LineHeightStyle(
            alignment = LineHeightStyle.Alignment.Proportional,
            trim = LineHeightStyle.Trim.None
        )
    )

    Box(modifier.background(Paper.paperTop)) {
        Canvas(Modifier.matchParentSize()) {
            val leftPx = Paper.leftInset.toPx()
            val topPx = Paper.topInset.toPx()
            val w = size.width
            val h = size.height

            // Warm paper shading.
            drawRect(Brush.verticalGradient(listOf(Paper.paperTop, Paper.paperBottom)))

            val lr = layout
            val defaultSpacing = Paper.lineHeight.toPx()
            // Uniform line spacing (single text style), derived from the layout.
            val spacing = if (lr != null && lr.lineCount > 1)
                (lr.lastBaseline - lr.firstBaseline) / (lr.lineCount - 1) else defaultSpacing
            val base0 = if (lr != null) lr.firstBaseline else defaultSpacing * 0.74f

            fun baselineY(i: Int): Float = topPx + base0 + i * spacing

            var i = 0
            while (true) {
                val y = baselineY(i)
                if (y > h - 4) break
                if (y > topPx) {
                    drawLine(Paper.rule.copy(alpha = 0.45f),
                        Offset(10f, y), Offset(w - 10f, y), strokeWidth = 1f)
                }
                i++
                if (i > 200) break
            }

            // Red double margin.
            val mx = leftPx - 12.dp.toPx()
            drawLine(Paper.margin.copy(alpha = 0.7f),
                Offset(mx, 6f), Offset(mx, h - 6f), strokeWidth = 1f)
            drawLine(Paper.margin.copy(alpha = 0.7f),
                Offset(mx + 3.dp.toPx(), 6f), Offset(mx + 3.dp.toPx(), h - 6f), strokeWidth = 1.6f)

            // Vignette.
            drawRect(
                Brush.radialGradient(
                    colors = listOf(Color.Transparent, Color.Black.copy(alpha = 0.06f)),
                    center = Offset(w / 2, h / 2),
                    radius = maxOf(w, h) * 0.7f
                )
            )
        }

        BasicTextField(
            value = tfv,
            onValueChange = { tfv = it; onTextChange(it.text) },
            readOnly = !editable,
            enabled = editable,
            textStyle = style,
            cursorBrush = SolidColor(Paper.ink),
            onTextLayout = { layout = it },
            modifier = Modifier
                .matchParentSize()
                .then(
                    if (editable) Modifier.pointerInput(pageKey) {
                        val leftPx = Paper.leftInset.toPx()
                        val topPx = Paper.topInset.toPx()
                        val spaceW = Paper.fontSize.toPx() * 0.28f
                        val defaultSpacing = Paper.lineHeight.toPx()
                        detectTapGestures { pos ->
                            handleTap(pos, tfv, layout, leftPx, topPx, defaultSpacing, spaceW) {
                                tfv = it; onTextChange(it.text)
                            }
                        }
                    } else Modifier
                )
                .padding(
                    start = Paper.leftInset,
                    top = Paper.topInset,
                    end = Paper.rightInset
                )
        )
    }
}

private fun handleTap(
    pos: Offset,
    value: TextFieldValue,
    layout: TextLayoutResult?,
    leftPx: Float,
    topPx: Float,
    defaultSpacing: Float,
    spaceW: Float,
    set: (TextFieldValue) -> Unit
) {
    val tx = pos.x - leftPx
    val ty = pos.y - topPx
    val spacing = if (layout != null && layout.lineCount > 1)
        (layout.lastBaseline - layout.firstBaseline) / (layout.lineCount - 1) else defaultSpacing
    val targetLine = maxOf(0, (ty / spacing).toInt())
    val targetCol = maxOf(0, (tx / spaceW).toInt())

    val lines = value.text.split("\n").toMutableList()
    val beyondLines = targetLine >= lines.size
    while (lines.size <= targetLine) lines.add("")
    val lineLen = lines[targetLine].length
    val beyondCol = lineLen < targetCol
    if (beyondCol) lines[targetLine] = lines[targetLine] + " ".repeat(targetCol - lineLen)

    if (beyondLines || beyondCol) {
        val newText = lines.joinToString("\n")
        var offset = 0
        for (i in 0 until targetLine) offset += lines[i].length + 1
        offset += targetCol
        set(TextFieldValue(newText, TextRange(offset.coerceIn(0, newText.length))))
    } else {
        val off = layout?.getOffsetForPosition(Offset(tx, ty)) ?: value.text.length
        set(value.copy(selection = TextRange(off.coerceIn(0, value.text.length))))
    }
}
