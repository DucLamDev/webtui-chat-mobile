package com.vpsttt.webtui_chat

import android.content.Context
import android.graphics.Bitmap
import android.os.Build
import android.media.MediaMetadataRetriever
import android.net.Uri
import android.os.Handler
import android.os.Looper
import androidx.annotation.OptIn
import androidx.media3.common.Effect
import androidx.media3.common.MediaItem
import androidx.media3.common.MimeTypes
import androidx.media3.common.util.UnstableApi
import androidx.media3.effect.Presentation
import androidx.media3.transformer.AudioEncoderSettings
import androidx.media3.transformer.Composition
import androidx.media3.transformer.DefaultEncoderFactory
import androidx.media3.transformer.EditedMediaItem
import androidx.media3.transformer.EditedMediaItemSequence
import androidx.media3.transformer.Effects
import androidx.media3.transformer.ExportException
import androidx.media3.transformer.ExportResult
import androidx.media3.transformer.ProgressHolder
import androidx.media3.transformer.Transformer
import androidx.media3.transformer.VideoEncoderSettings
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileOutputStream
import java.util.concurrent.Executors

/**
 * Kênh `webtui/video_compress`: nén video bằng Media3 Transformer
 * (cạnh ngắn về `shortSide`, H.264 + AAC, MP4). Mọi hàm chạy trên luồng chính.
 */
@OptIn(UnstableApi::class)
class VideoCompressChannel(
    private val context: Context,
    messenger: BinaryMessenger,
) : MethodChannel.MethodCallHandler {
    private class Job(
        val transformer: Transformer,
        val partFile: File,
        val result: MethodChannel.Result,
    ) {
        var cancelled = false
        var finished = false
    }

    private val channel = MethodChannel(messenger, "webtui/video_compress")
    private val handler = Handler(Looper.getMainLooper())
    private val jobs = HashMap<String, Job>()
    private val posterExecutor = Executors.newSingleThreadExecutor()

    init {
        channel.setMethodCallHandler(this)
    }

    fun dispose() {
        channel.setMethodCallHandler(null)
        posterExecutor.shutdown()
        for (job in jobs.values.toList()) {
            finishCancelled(job)
        }
        jobs.clear()
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "compress" -> compress(call, result)
            "poster" -> poster(call, result)
            "cancel" -> {
                val id = call.argument<String>("id")
                val job = if (id == null) null else jobs[id]
                if (id != null && job != null) {
                    cancelJob(id, job)
                }
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    private fun compress(call: MethodCall, result: MethodChannel.Result) {
        val id = call.argument<String>("id")
        val input = call.argument<String>("input")
        val output = call.argument<String>("output")
        val shortSide = call.argument<Number>("shortSide")?.toInt()
        val videoBitrate = call.argument<Number>("videoBitrate")?.toInt()
        val audioBitrate = call.argument<Number>("audioBitrate")?.toInt()
        if (id.isNullOrEmpty() || input.isNullOrEmpty() || output.isNullOrEmpty() ||
            shortSide == null || videoBitrate == null || audioBitrate == null
        ) {
            result.error("INVALID_ARGUMENTS", "Thiếu tham số nén video.", null)
            return
        }
        if (jobs.containsKey(id)) {
            result.error("BUSY", "Lượt nén này đang chạy.", null)
            return
        }
        val inputFile = File(input)
        if (!inputFile.isFile) {
            result.error("INPUT_MISSING", "Không thấy tệp video nguồn.", null)
            return
        }
        val outputFile = File(output)
        val partFile = File("$output.part")
        try {
            outputFile.parentFile?.mkdirs()
            partFile.delete()

            val videoEffects = ArrayList<Effect>()
            val shortestSide = readShortestSide(inputFile)
            // Chỉ thu nhỏ, không phóng to video đã nhỏ.
            if (shortestSide == null || shortestSide > shortSide) {
                videoEffects.add(Presentation.createForShortSide(shortSide))
            }
            val edited = EditedMediaItem.Builder(
                MediaItem.fromUri(Uri.fromFile(inputFile))
            )
                .setEffects(Effects(emptyList(), videoEffects))
                .build()
            val composition = Composition.Builder(
                EditedMediaItemSequence.Builder(edited).build()
            )
                .setHdrMode(Composition.HDR_MODE_TONE_MAP_HDR_TO_SDR_USING_OPEN_GL)
                .build()

            val encoderFactory = DefaultEncoderFactory.Builder(context)
                .setRequestedVideoEncoderSettings(
                    VideoEncoderSettings.Builder().setBitrate(videoBitrate).build()
                )
                .setRequestedAudioEncoderSettings(
                    AudioEncoderSettings.Builder().setBitrate(audioBitrate).build()
                )
                .setEnableFallback(true)
                .build()

            lateinit var job: Job
            val listener = object : Transformer.Listener {
                override fun onCompleted(composition: Composition, exportResult: ExportResult) {
                    if (job.finished) return
                    job.finished = true
                    jobs.remove(id)
                    val ok = try {
                        outputFile.delete()
                        partFile.renameTo(outputFile) && outputFile.length() > 0
                    } catch (_: SecurityException) {
                        false
                    }
                    if (ok) {
                        result.success(
                            mapOf("path" to outputFile.path, "byteSize" to outputFile.length())
                        )
                    } else {
                        partFile.delete()
                        result.error("OUTPUT_FAILED", "Không ghi được tệp video nén.", null)
                    }
                }

                override fun onError(
                    composition: Composition,
                    exportResult: ExportResult,
                    exportException: ExportException,
                ) {
                    if (job.finished) return
                    job.finished = true
                    jobs.remove(id)
                    partFile.delete()
                    result.error(
                        "COMPRESS_FAILED",
                        exportException.message ?: "Nén video lỗi.",
                        null,
                    )
                }
            }
            val transformer = Transformer.Builder(context)
                .setVideoMimeType(MimeTypes.VIDEO_H264)
                .setAudioMimeType(MimeTypes.AUDIO_AAC)
                .setEncoderFactory(encoderFactory)
                .addListener(listener)
                .build()
            job = Job(transformer, partFile, result)
            jobs[id] = job
            transformer.start(composition, partFile.path)
            pollProgress(id, job)
        } catch (e: Exception) {
            jobs.remove(id)
            partFile.delete()
            result.error("COMPRESS_FAILED", e.message ?: "Không bắt đầu được nén video.", null)
        }
    }

    /**
     * Lấy một khung hình làm ảnh bìa (JPEG, cạnh dài tối đa `maxSide`) và đọc
     * kích thước / thời lượng video. Chạy ngoài luồng chính.
     */
    private fun poster(call: MethodCall, result: MethodChannel.Result) {
        val input = call.argument<String>("input")
        val output = call.argument<String>("output")
        val maxSide = call.argument<Number>("maxSide")?.toInt() ?: 480
        val timeMs = call.argument<Number>("timeMs")?.toLong() ?: 1000L
        if (input.isNullOrEmpty() || output.isNullOrEmpty() || maxSide <= 0) {
            result.error("INVALID_ARGUMENTS", "Thiếu tham số lấy ảnh bìa.", null)
            return
        }
        val inputFile = File(input)
        if (!inputFile.isFile) {
            result.error("INPUT_MISSING", "Không thấy tệp video nguồn.", null)
            return
        }
        try {
            posterExecutor.execute {
                val outcome = try {
                    Result.success(extractPoster(inputFile, File(output), maxSide, timeMs))
                } catch (e: Exception) {
                    Result.failure<Map<String, Any>>(e)
                }
                handler.post {
                    outcome.fold(
                        onSuccess = { result.success(it) },
                        onFailure = {
                            result.error(
                                "POSTER_FAILED",
                                it.message ?: "Không lấy được ảnh bìa.",
                                null,
                            )
                        },
                    )
                }
            }
        } catch (e: Exception) {
            result.error("POSTER_FAILED", e.message ?: "Không lấy được ảnh bìa.", null)
        }
    }

    private fun extractPoster(
        input: File,
        output: File,
        maxSide: Int,
        timeMs: Long,
    ): Map<String, Any> {
        val partFile = File("${output.path}.part")
        val retriever = MediaMetadataRetriever()
        try {
            retriever.setDataSource(input.path)
            fun meta(key: Int) = retriever.extractMetadata(key)?.toLongOrNull()
            val durationMs = meta(MediaMetadataRetriever.METADATA_KEY_DURATION) ?: 0L
            val rawWidth = meta(MediaMetadataRetriever.METADATA_KEY_VIDEO_WIDTH)?.toInt() ?: 0
            val rawHeight = meta(MediaMetadataRetriever.METADATA_KEY_VIDEO_HEIGHT)?.toInt() ?: 0
            val rotation = meta(MediaMetadataRetriever.METADATA_KEY_VIDEO_ROTATION)?.toInt() ?: 0
            // Kích thước theo chiều hiển thị: xoay 90 / 270 thì đổi chỗ.
            val swap = rotation == 90 || rotation == 270
            val width = if (swap) rawHeight else rawWidth
            val height = if (swap) rawWidth else rawHeight

            // Video ngắn hơn mốc yêu cầu thì lấy giữa video.
            val atMs = if (durationMs in 1..timeMs) durationMs / 2 else timeMs
            val atUs = atMs * 1000L
            var frame: Bitmap? = null
            if (Build.VERSION.SDK_INT >= 27 && width > 0 && height > 0) {
                val scale = minOf(1.0, maxSide.toDouble() / maxOf(width, height))
                val dstW = maxOf(1, Math.round(width * scale).toInt())
                val dstH = maxOf(1, Math.round(height * scale).toInt())
                frame = retriever.getScaledFrameAtTime(
                    atUs,
                    MediaMetadataRetriever.OPTION_CLOSEST_SYNC,
                    dstW,
                    dstH,
                )
            }
            if (frame == null) {
                frame = retriever.getFrameAtTime(atUs, MediaMetadataRetriever.OPTION_CLOSEST_SYNC)
                    ?: retriever.getFrameAtTime(-1)
            }
            if (frame == null) throw IllegalStateException("Không đọc được khung hình.")
            var bitmap: Bitmap = frame
            val longest = maxOf(bitmap.width, bitmap.height)
            if (longest > maxSide) {
                val scale = maxSide.toDouble() / longest
                val scaled = Bitmap.createScaledBitmap(
                    bitmap,
                    maxOf(1, Math.round(bitmap.width * scale).toInt()),
                    maxOf(1, Math.round(bitmap.height * scale).toInt()),
                    true,
                )
                if (scaled !== bitmap) {
                    bitmap.recycle()
                    bitmap = scaled
                }
            }
            output.parentFile?.mkdirs()
            partFile.delete()
            val ok = FileOutputStream(partFile).use { stream ->
                bitmap.compress(Bitmap.CompressFormat.JPEG, 80, stream)
            }
            val outWidth = if (width > 0) width else bitmap.width
            val outHeight = if (height > 0) height else bitmap.height
            bitmap.recycle()
            if (!ok || partFile.length() <= 0L) throw IllegalStateException("Không ghi được ảnh bìa.")
            output.delete()
            if (!partFile.renameTo(output)) throw IllegalStateException("Không ghi được ảnh bìa.")
            return mapOf(
                "path" to output.path,
                "byteSize" to output.length(),
                "width" to outWidth,
                "height" to outHeight,
                "durationMs" to durationMs,
            )
        } finally {
            partFile.delete()
            try {
                retriever.release()
            } catch (_: Exception) {
            }
        }
    }

    private fun pollProgress(id: String, job: Job) {
        handler.postDelayed({
            if (job.finished || job.cancelled || jobs[id] !== job) return@postDelayed
            val holder = ProgressHolder()
            if (job.transformer.getProgress(holder) == Transformer.PROGRESS_STATE_AVAILABLE) {
                channel.invokeMethod(
                    "progress",
                    mapOf("id" to id, "progress" to holder.progress / 100.0),
                )
            }
            pollProgress(id, job)
        }, 300)
    }

    private fun cancelJob(id: String, job: Job) {
        jobs.remove(id)
        finishCancelled(job)
    }

    private fun finishCancelled(job: Job) {
        if (job.finished) return
        job.finished = true
        job.cancelled = true
        try {
            job.transformer.cancel()
        } catch (_: Exception) {
        }
        job.partFile.delete()
        job.result.error("CANCELLED", "Đã huỷ nén video.", null)
    }

    /** Cạnh ngắn theo chiều hiển thị (đã tính xoay); null nếu không đọc được. */
    private fun readShortestSide(file: File): Int? {
        val retriever = MediaMetadataRetriever()
        return try {
            retriever.setDataSource(file.path)
            val width = retriever
                .extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_WIDTH)
                ?.toIntOrNull()
            val height = retriever
                .extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_HEIGHT)
                ?.toIntOrNull()
            if (width == null || height == null) null else minOf(width, height)
        } catch (_: Exception) {
            null
        } finally {
            try {
                retriever.release()
            } catch (_: Exception) {
            }
        }
    }
}
