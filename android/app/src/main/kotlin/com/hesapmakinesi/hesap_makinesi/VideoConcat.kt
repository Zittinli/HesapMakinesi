package com.hesapmakinesi.hesap_makinesi

import android.media.MediaCodec
import android.media.MediaExtractor
import android.media.MediaMuxer
import java.io.File
import java.nio.ByteBuffer

object VideoConcat {
    fun concat(inputs: List<String>, output: String) {
        require(inputs.size >= 2) { "En az iki parça gerekir." }
        val dest = File(output)
        dest.parentFile?.mkdirs()
        if (dest.exists()) dest.delete()

        val muxer = MediaMuxer(output, MediaMuxer.OutputFormat.MUXER_OUTPUT_MPEG_4)
        var videoTrack = -1
        var audioTrack = -1
        var started = false
        var videoTimeUs = 0L
        var audioTimeUs = 0L

        try {
            for (path in inputs) {
                val extractor = MediaExtractor()
                extractor.setDataSource(path)
                var sourceVideo = -1
                var sourceAudio = -1
                for (index in 0 until extractor.trackCount) {
                    val mime = extractor.getTrackFormat(index).getString("mime").orEmpty()
                    if (mime.startsWith("video/") && sourceVideo < 0) {
                        sourceVideo = index
                    } else if (mime.startsWith("audio/") && sourceAudio < 0) {
                        sourceAudio = index
                    }
                }
                if (!started) {
                    if (sourceVideo >= 0) {
                        videoTrack = muxer.addTrack(extractor.getTrackFormat(sourceVideo))
                    }
                    if (sourceAudio >= 0) {
                        audioTrack = muxer.addTrack(extractor.getTrackFormat(sourceAudio))
                    }
                    muxer.start()
                    started = true
                }
                val clipVideoUs = copyTrack(
                    extractor = extractor,
                    sourceTrack = sourceVideo,
                    destTrack = videoTrack,
                    muxer = muxer,
                    timeOffsetUs = videoTimeUs,
                )
                val clipAudioUs = copyTrack(
                    extractor = extractor,
                    sourceTrack = sourceAudio,
                    destTrack = audioTrack,
                    muxer = muxer,
                    timeOffsetUs = audioTimeUs,
                )
                videoTimeUs += maxOf(clipVideoUs, clipAudioUs)
                audioTimeUs = videoTimeUs
                extractor.release()
            }
        } finally {
            if (started) {
                muxer.stop()
            }
            muxer.release()
        }
    }

    private fun copyTrack(
        extractor: MediaExtractor,
        sourceTrack: Int,
        destTrack: Int,
        muxer: MediaMuxer,
        timeOffsetUs: Long,
    ): Long {
        if (sourceTrack < 0 || destTrack < 0) return 0
        extractor.selectTrack(sourceTrack)
        val maxSize = extractor.getTrackFormat(sourceTrack).let { format ->
            if (format.containsKey("max-input-size")) {
                maxOf(format.getInteger("max-input-size"), 256 * 1024)
            } else {
                2 * 1024 * 1024
            }
        }
        val buffer = ByteBuffer.allocate(maxSize)
        val info = MediaCodec.BufferInfo()
        var lastPts = 0L
        while (true) {
            val size = extractor.readSampleData(buffer, 0)
            if (size < 0) break
            info.offset = 0
            info.size = size
            info.flags = extractor.sampleFlags
            info.presentationTimeUs = extractor.sampleTime + timeOffsetUs
            lastPts = info.presentationTimeUs
            muxer.writeSampleData(destTrack, buffer, info)
            extractor.advance()
        }
        extractor.unselectTrack(sourceTrack)
        return if (lastPts <= timeOffsetUs) 0 else lastPts - timeOffsetUs
    }
}
