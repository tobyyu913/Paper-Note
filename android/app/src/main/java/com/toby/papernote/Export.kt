package com.toby.papernote

import android.content.ContentValues
import android.content.Context
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color as AColor
import android.graphics.LinearGradient
import android.graphics.Paint
import android.graphics.Shader
import android.graphics.pdf.PdfDocument
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import android.text.StaticLayout
import android.text.TextPaint
import androidx.compose.ui.graphics.toArgb
import androidx.core.content.res.ResourcesCompat
import java.io.File
import java.io.FileOutputStream

object PageExporter {
    /** Renders a page to a PNG and saves it as "<title>-P<n>.png" in Pictures/note book. */
    fun capture(context: Context, notebook: Notebook, pageIndex: Int): Result<String> = runCatching {
        val bmp = renderPage(context, notebook, pageIndex)
        val name = "${safeTitle(notebook)}-P${pageIndex + 1}.png"
        saveBitmap(context, bmp, name)
        "Pictures/note book/$name"
    }

    /** Renders every page into one multi-page PDF saved as "<title>.pdf" in Documents/note book. */
    fun exportPdf(context: Context, notebook: Notebook): Result<String> = runCatching {
        val doc = PdfDocument()
        try {
            notebook.pages.forEachIndexed { i, _ ->
                val bmp = renderPage(context, notebook, i)
                val info = PdfDocument.PageInfo.Builder(bmp.width, bmp.height, i + 1).create()
                val page = doc.startPage(info)
                page.canvas.drawBitmap(bmp, 0f, 0f, null)
                doc.finishPage(page)
            }
            val name = "${safeTitle(notebook)}.pdf"
            savePdf(context, doc, name)
            "Documents/note book/$name"
        } finally {
            doc.close()
        }
    }

    private fun safeTitle(notebook: Notebook): String = notebook.title
        .replace(Regex("[/\\\\:*?\"<>|]"), "-")
        .trim()
        .ifEmpty { "Untitled" }

    /** Draws one page (ruled paper + text) into a bitmap. */
    private fun renderPage(context: Context, notebook: Notebook, pageIndex: Int): Bitmap {
        val w = 1080
        val h = (w / Paper.aspect).toInt()
        val leftInset = w * 0.135f
        val rightInset = w * 0.055f
        val topInset = h * 0.046f
        val fontPx = w * 0.0545f
        val rowHeight = fontPx * (30f / 18f)

        val bmp = Bitmap.createBitmap(w, h, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(bmp)

        // Paper gradient.
        val bg = Paint().apply {
            shader = LinearGradient(
                0f, 0f, 0f, h.toFloat(),
                Paper.paperTop.toArgb(), Paper.paperBottom.toArgb(), Shader.TileMode.CLAMP
            )
        }
        canvas.drawRect(0f, 0f, w.toFloat(), h.toFloat(), bg)

        // Text layout (handles wrapping + newlines).
        val typeface = ResourcesCompat.getFont(context, R.font.handwriting)
        val tp = TextPaint(Paint.ANTI_ALIAS_FLAG).apply {
            this.typeface = typeface
            textSize = fontPx
            color = Paper.ink.toArgb()
        }
        val fm = tp.fontMetrics
        val extra = (rowHeight - (fm.descent - fm.ascent)).coerceAtLeast(0f)
        val text = notebook.pages.getOrElse(pageIndex) { "" }
        val textWidth = (w - leftInset - rightInset).toInt()
        val layout = StaticLayout.Builder
            .obtain(text, 0, text.length, tp, textWidth)
            .setLineSpacing(extra, 1f)
            .build()

        // Rules at baselines.
        val rule = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = Paper.rule.copy(alpha = 0.45f).toArgb()
            strokeWidth = w * 0.0012f
        }
        val spacing = if (layout.lineCount > 1)
            (layout.getLineBaseline(1) - layout.getLineBaseline(0)).toFloat() else rowHeight
        var i = 0
        while (true) {
            val y = if (i < layout.lineCount) topInset + layout.getLineBaseline(i)
            else topInset + layout.getLineBaseline(layout.lineCount - 1) +
                    (i - (layout.lineCount - 1)) * spacing
            if (y > h - 6) break
            if (y > topInset) canvas.drawLine(12f, y, w - 12f, y, rule)
            i++
            if (i > 300) break
        }

        // Red margin.
        val margin = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = Paper.margin.copy(alpha = 0.7f).toArgb()
            strokeWidth = w * 0.0016f
        }
        val mx = leftInset - w * 0.022f
        canvas.drawLine(mx, 8f, mx, h - 8f, margin)
        canvas.drawLine(mx + w * 0.006f, 8f, mx + w * 0.006f, h - 8f, margin)

        // Draw the text.
        canvas.save()
        canvas.translate(leftInset, topInset)
        layout.draw(canvas)
        canvas.restore()

        return bmp
    }

    private fun saveBitmap(context: Context, bmp: Bitmap, name: String) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            val values = ContentValues().apply {
                put(MediaStore.Images.Media.DISPLAY_NAME, name)
                put(MediaStore.Images.Media.MIME_TYPE, "image/png")
                put(MediaStore.Images.Media.RELATIVE_PATH, "Pictures/note book")
            }
            val resolver = context.contentResolver
            val uri = resolver.insert(MediaStore.Images.Media.EXTERNAL_CONTENT_URI, values)
                ?: throw IllegalStateException("Could not create file")
            resolver.openOutputStream(uri).use { out ->
                bmp.compress(Bitmap.CompressFormat.PNG, 100, out!!)
            }
        } else {
            val dir = File(
                Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_PICTURES),
                "note book"
            )
            dir.mkdirs()
            FileOutputStream(File(dir, name)).use { out ->
                bmp.compress(Bitmap.CompressFormat.PNG, 100, out)
            }
        }
    }

    private fun savePdf(context: Context, doc: PdfDocument, name: String) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            val values = ContentValues().apply {
                put(MediaStore.MediaColumns.DISPLAY_NAME, name)
                put(MediaStore.MediaColumns.MIME_TYPE, "application/pdf")
                put(MediaStore.MediaColumns.RELATIVE_PATH, "Documents/note book")
            }
            val resolver = context.contentResolver
            val uri = resolver.insert(MediaStore.Files.getContentUri("external"), values)
                ?: throw IllegalStateException("Could not create file")
            resolver.openOutputStream(uri).use { out ->
                doc.writeTo(out!!)
            }
        } else {
            val dir = File(
                Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOCUMENTS),
                "note book"
            )
            dir.mkdirs()
            FileOutputStream(File(dir, name)).use { out ->
                doc.writeTo(out)
            }
        }
    }
}
