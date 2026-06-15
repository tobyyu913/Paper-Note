package com.toby.papernote

import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.Font
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp

/** Handwriting font bundled in res/font. */
val Handwriting = FontFamily(Font(R.font.handwriting))

object Paper {
    // Page geometry (the page is scaled to fit, keeping this aspect ratio).
    val aspect = 0.72f

    // Ink and paper.
    val ink = Color(0xFF213073)
    val paperTop = Color(0xFFFAF2DB)
    val paperBottom = Color(0xFFF3E6C4)
    val rule = Color(0xFF6B8CC7)
    val margin = Color(0xFFD14749)

    // Desk.
    val desk = Color(0xFF4D3829)
    val deskDark = Color(0xFF2E2117)

    // Text layout (also used to draw rules at the baselines).
    val fontSize = 18.sp
    val lineHeight = 30.sp
    val leftInset = 46.dp
    val topInset = 22.dp
    val rightInset = 20.dp
}

/** Leather cover palettes: base, highlight, stitch. */
data class Leather(val base: Color, val high: Color, val stitch: Color)

val leathers = listOf(
    Leather(Color(0xFF663320), Color(0xFF8C4D2E), Color(0xFFD9BC8C)), // brown
    Leather(Color(0xFF21382E), Color(0xFF335442), Color(0xFFCCC799)), // forest
    Leather(Color(0xFF332952), Color(0xFF4D3D73), Color(0xFFD1C79E)), // plum
    Leather(Color(0xFF61191F), Color(0xFF85292E), Color(0xFFDBC28F)), // oxblood
    Leather(Color(0xFF1A1A1F), Color(0xFF333338), Color(0xFFB3B3B8)), // charcoal
)
