package dev.doclens.doclens

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertTrue

class SubjectAlphaMatteTest {
    @Test
    fun aiConfidencePreservesOpaqueForegroundAndTransparentBackground() {
        val original = IntArray(500) { 0xFFE34455.toInt() }
        val confidence = FloatArray(500) { i ->
            when {
                i < 100 -> 0f
                i < 200 -> .5f
                else -> 1f
            }
        }
        val pixels = SubjectAlphaMatte.composite(original, confidence, null)
        assertEquals(0, pixels[0])
        val softened = pixels[150] ushr 24
        assertTrue(softened in 100..155)
        assertEquals(0xFFE34455.toInt(), pixels[300])
    }

    @Test
    fun backgroundReplacementUsesAlphaBlendingWithoutLosingSubject() {
        val original = IntArray(500) { 0xFFDD2211.toInt() }
        val confidence = FloatArray(500) { i -> if (i < 200) 0f else 1f }
        val pixels = SubjectAlphaMatte.composite(
            original, confidence, 0xFF4477AA.toInt(),
        )
        assertEquals(0xFF4477AA.toInt(), pixels[5])
        assertEquals(0xFFDD2211.toInt(), pixels[400])
    }

    @Test
    fun missingAiSubjectFailsWithoutWritingEmptyPng() {
        val source = IntArray(500) { 0xFF332211.toInt() }
        assertFailsWith<IllegalStateException> {
            SubjectAlphaMatte.composite(source, FloatArray(500), null)
        }
    }
}
