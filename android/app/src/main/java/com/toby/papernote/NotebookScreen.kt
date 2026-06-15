package com.toby.papernote

import android.widget.Toast
import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.tween
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.ChevronLeft
import androidx.compose.material.icons.filled.ChevronRight
import androidx.compose.material.icons.filled.MenuBook
import androidx.compose.material.icons.filled.PhotoCamera
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.TransformOrigin
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import kotlinx.coroutines.launch
import kotlin.math.abs

@Composable
fun NotebookScreen(store: NotebookStore, index: Int) {
    val notebook = store.notebooks[index]
    val context = LocalContext.current
    val density = LocalDensity.current.density
    val scope = rememberCoroutineScope()
    val sounds = remember { Sounds() }

    val coverAnim = remember { Animatable(0f) }   // 0 closed, 1 open
    val turnAnim = remember { Animatable(0f) }
    var turning by remember { mutableStateOf(false) }
    var turnForward by remember { mutableStateOf(true) }
    var topIndex by remember { mutableIntStateOf(0) }
    var bottomIndex by remember { mutableIntStateOf(0) }
    var page by remember { mutableIntStateOf(0) }

    val coverOpen = coverAnim.value > 0.99f

    fun textOf(i: Int) = store.notebooks[index].pages.getOrElse(i) { "" }
    fun setPage(i: Int, newText: String) {
        store.update(index) { nb ->
            val m = nb.pages.toMutableList()
            if (i in m.indices) m[i] = newText
            nb.copy(pages = m)
        }
    }

    fun goForward() {
        if (turning) return
        if (coverAnim.value <= 0.99f) {
            scope.launch {
                sounds.stud()
                coverAnim.animateTo(1f, tween(500))
            }
        } else {
            val last = store.notebooks[index].pageCount - 1
            if (page >= last) store.update(index) { it.copy(pages = it.pages + "") }
            topIndex = page; bottomIndex = page + 1
            turnForward = true; turning = true
            scope.launch {
                sounds.flip()
                turnAnim.snapTo(0f)
                turnAnim.animateTo(1f, tween(550))
                page += 1; turning = false
            }
        }
    }

    fun goBackward() {
        if (turning) return
        if (coverAnim.value <= 0.99f) return
        if (page == 0) {
            scope.launch {
                coverAnim.animateTo(0f, tween(500))
                sounds.stud()
            }
        } else {
            topIndex = page - 1; bottomIndex = page
            turnForward = false; turning = true
            scope.launch {
                sounds.flip()
                turnAnim.snapTo(0f)
                turnAnim.animateTo(1f, tween(550))
                page -= 1; turning = false
            }
        }
    }

    fun capture() {
        val result = PageExporter.capture(context, store.notebooks[index], page)
        val msg = result.getOrNull()?.let { "Saved to $it" } ?: "Save failed"
        Toast.makeText(context, msg, Toast.LENGTH_SHORT).show()
    }

    Column(Modifier.fillMaxSize().background(Paper.desk)) {
        // Top bar.
        Row(
            Modifier.fillMaxWidth().padding(horizontal = 12.dp, vertical = 8.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            IconButton(onClick = { store.openIndex = null }) {
                Icon(Icons.Filled.MenuBook, "Shelf", tint = Color.White.copy(alpha = 0.85f))
            }
            Spacer(Modifier.width(8.dp))
            // Leather swatches.
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                leathers.forEachIndexed { i, l ->
                    Box(
                        Modifier.size(20.dp)
                            .clip(CircleShape)
                            .background(l.base)
                            .border(
                                width = if (notebook.leather == i) 2.dp else 1.dp,
                                color = if (notebook.leather == i) Color.White.copy(alpha = 0.9f)
                                else Color.White.copy(alpha = 0.2f),
                                shape = CircleShape
                            )
                            .clickable(
                                interactionSource = remember { MutableInteractionSource() },
                                indication = null
                            ) { store.update(index) { it.copy(leather = i) } }
                    )
                }
            }
            Spacer(Modifier.width(1.dp).weight(1f))
            IconButton(onClick = { capture() }, enabled = coverOpen && !turning) {
                Icon(Icons.Filled.PhotoCamera, "Save page as PNG", tint = Color.White.copy(alpha = if (coverOpen) 0.85f else 0.3f))
            }
        }

        BoxWithConstraints(
            Modifier.weight(1f).fillMaxWidth(),
            contentAlignment = Alignment.Center
        ) {
            val availH = maxHeight - 16.dp
            val availW = maxWidth - 24.dp
            var pw = availW
            var ph = pw / Paper.aspect
            if (ph > availH) { ph = availH; pw = ph * Paper.aspect }
            val pageW = pw
            val pageH = ph

            Box(contentAlignment = Alignment.Center) {
                // Thickness edges.
                val after = (store.notebooks[index].pageCount - 1 - page).coerceAtLeast(0)
                BookEdge(after, pageH, true,
                    Modifier.align(Alignment.Center).offset(x = pageW / 2 + edgeThk(after) / 2))
                if (coverOpen) {
                    BookEdge(page, pageH, false,
                        Modifier.align(Alignment.Center).offset(x = -(pageW / 2 + edgeThk(page) / 2)))
                }

                // Page stack.
                Box(Modifier.size(pageW, pageH).clip(RoundedCornerShape(6.dp))) {
                    if (turning) {
                        PageSurface(bottomIndex, textOf(bottomIndex), false, {}, Modifier.fillMaxSize())
                        val angle = if (turnForward) -105f * turnAnim.value else -105f * (1 - turnAnim.value)
                        val lift = abs(angle) / 105f
                        Box(
                            Modifier.fillMaxSize().graphicsLayer {
                                rotationY = angle
                                cameraDistance = 16f * density
                                transformOrigin = TransformOrigin(0f, 0.5f)
                            }
                        ) {
                            PageSurface(topIndex, textOf(topIndex), false, {}, Modifier.fillMaxSize())
                            Box(
                                Modifier.fillMaxSize().background(
                                    Brush.horizontalGradient(
                                        listOf(Color.Black.copy(alpha = 0.28f * lift), Color.Transparent)
                                    )
                                )
                            )
                        }
                    } else {
                        PageSurface(
                            pageKey = page,
                            initialText = textOf(page),
                            editable = coverOpen,
                            onTextChange = { setPage(page, it) },
                            modifier = Modifier.fillMaxSize()
                        )
                    }
                }

                // Cover (while not fully open).
                if (coverAnim.value < 0.999f) {
                    val cAngle = -168f * coverAnim.value
                    Box(
                        Modifier.size(pageW, pageH).graphicsLayer {
                            rotationY = cAngle
                            cameraDistance = 16f * density
                            transformOrigin = TransformOrigin(0f, 0.5f)
                            alpha = if (coverAnim.value > 0.5f) 0f else 1f
                        }.clip(RoundedCornerShape(14.dp))
                    ) {
                        CoverView(
                            notebook = notebook,
                            onUpdate = { store.update(index) { _ -> it } },
                            onOpenStud = { goForward() },
                            modifier = Modifier.fillMaxSize()
                        )
                    }
                }
            }
        }

        // Bottom navigation.
        Row(
            Modifier.fillMaxWidth().padding(horizontal = 12.dp, vertical = 10.dp),
            horizontalArrangement = Arrangement.Center,
            verticalAlignment = Alignment.CenterVertically
        ) {
            IconButton(onClick = { goBackward() }) {
                Icon(Icons.Filled.ChevronLeft, "Previous", tint = Color.White.copy(alpha = 0.85f))
            }
            Text(
                if (coverOpen) "Page ${page + 1} of ${notebook.pageCount}" else "Cover",
                color = Color.White.copy(alpha = 0.8f),
                fontSize = 14.sp,
                modifier = Modifier.width(150.dp),
                textAlign = androidx.compose.ui.text.style.TextAlign.Center
            )
            IconButton(onClick = { goForward() }) {
                Icon(Icons.Filled.ChevronRight, "Next", tint = Color.White.copy(alpha = 0.85f))
            }
        }
    }
}

private fun edgeThk(n: Int): Dp = minOf(22f, n * 0.55f).dp

@Composable
private fun BookEdge(pageCount: Int, height: Dp, trailing: Boolean, modifier: Modifier) {
    val thickness = edgeThk(pageCount)
    if (thickness.value < 0.5f) {
        Box(modifier.size(width = 0.5.dp, height = height))
        return
    }
    Canvas(modifier.size(width = thickness, height = height - 8.dp)) {
        drawRect(Paper.paperBottom)
        var x = if (trailing) 0f else size.width
        val step = 0.9.dp.toPx()
        var k = 0
        while (x in 0f..size.width) {
            val shade = if (k % 3 == 0) 0.14f else 0.06f
            drawLine(Color.Black.copy(alpha = shade), Offset(x, 1f), Offset(x, size.height - 1f), strokeWidth = 0.5.dp.toPx())
            x += if (trailing) step else -step
            k++
        }
    }
}

