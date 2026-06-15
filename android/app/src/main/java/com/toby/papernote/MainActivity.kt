package com.toby.papernote

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.systemBarsPadding
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        val store = NotebookStore(this)
        setContent { App(store) }
    }
}

@Composable
fun App(store: NotebookStore) {
    val open = store.openIndex
    if (open != null && open in store.notebooks.indices) {
        NotebookScreen(store, open)
    } else {
        LibraryScreen(store)
    }
}

@Composable
fun LibraryScreen(store: NotebookStore) {
    Box(Modifier.fillMaxSize().background(Paper.deskDark)) {
        Column(Modifier.fillMaxSize().systemBarsPadding()) {
            Text(
                "My Notebooks",
                color = Color.White.copy(alpha = 0.92f),
                fontFamily = Handwriting,
                fontWeight = FontWeight.Bold,
                fontSize = 30.sp,
                modifier = Modifier.padding(start = 20.dp, top = 16.dp, bottom = 8.dp)
            )
            LazyVerticalGrid(
                columns = GridCells.Adaptive(150.dp),
                contentPadding = androidx.compose.foundation.layout.PaddingValues(16.dp),
                horizontalArrangement = Arrangement.spacedBy(16.dp),
                verticalArrangement = Arrangement.spacedBy(16.dp),
                modifier = Modifier.fillMaxSize()
            ) {
                items(store.notebooks, key = { it.id }) { nb ->
                    val idx = store.notebooks.indexOfFirst { it.id == nb.id }
                    Spine(nb) { if (idx >= 0) store.openIndex = idx }
                }
                item {
                    NewSpine { store.openIndex = store.newNotebook() }
                }
            }
        }
    }
}

@Composable
private fun Spine(nb: Notebook, onOpen: () -> Unit) {
    val p = nb.palette
    Column(horizontalAlignment = Alignment.CenterHorizontally) {
        Box(
            Modifier
                .fillMaxWidth()
                .height(210.dp)
                .clip(RoundedCornerShape(8.dp))
                .background(Brush.linearGradient(listOf(p.high, p.base)))
                .clickable(
                    interactionSource = remember { MutableInteractionSource() },
                    indication = null
                ) { onOpen() },
            contentAlignment = Alignment.Center
        ) {
            // Binding shading on the left.
            Box(
                Modifier.fillMaxWidth().height(210.dp).background(
                    Brush.horizontalGradient(
                        0f to Color.Black.copy(alpha = 0.35f),
                        0.12f to Color.Transparent
                    )
                )
            )
            Column(
                Modifier.padding(12.dp),
                horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.spacedBy(6.dp)
            ) {
                Text(
                    nb.title.ifEmpty { "Untitled" },
                    color = Color.White.copy(alpha = 0.92f),
                    fontFamily = Handwriting,
                    fontWeight = FontWeight.Bold,
                    fontSize = 19.sp,
                    textAlign = TextAlign.Center
                )
                if (nb.writer.isNotEmpty()) {
                    Text(
                        nb.writer,
                        color = Color.White.copy(alpha = 0.7f),
                        fontFamily = Handwriting,
                        fontSize = 13.sp,
                        textAlign = TextAlign.Center
                    )
                }
            }
        }
        Text(
            "${nb.pages.size} page${if (nb.pages.size == 1) "" else "s"}",
            color = Color.White.copy(alpha = 0.5f),
            fontSize = 11.sp,
            modifier = Modifier.padding(top = 6.dp)
        )
    }
}

@Composable
private fun NewSpine(onNew: () -> Unit) {
    Column(horizontalAlignment = Alignment.CenterHorizontally) {
        Box(
            Modifier
                .fillMaxWidth()
                .height(210.dp)
                .clip(RoundedCornerShape(8.dp))
                .background(Color.White.copy(alpha = 0.06f))
                .clickable(
                    interactionSource = remember { MutableInteractionSource() },
                    indication = null
                ) { onNew() },
            contentAlignment = Alignment.Center
        ) {
            Column(horizontalAlignment = Alignment.CenterHorizontally) {
                Icon(Icons.Filled.Add, "New", tint = Color.White.copy(alpha = 0.55f))
                Text("New Notebook", color = Color.White.copy(alpha = 0.55f), fontSize = 13.sp)
            }
        }
        Text(" ", fontSize = 11.sp, modifier = Modifier.padding(top = 6.dp))
    }
}
