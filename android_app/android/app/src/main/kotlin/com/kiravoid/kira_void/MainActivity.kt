package com.kiravoid.kira_void

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.os.Handler
import android.os.Looper
import com.google.mediapipe.framework.image.BitmapExtractor
import com.google.mediapipe.framework.image.BitmapImageBuilder
import com.google.mediapipe.tasks.core.BaseOptions
import com.google.mediapipe.tasks.vision.imagegenerator.ImageGenerator
import com.google.mediapipe.tasks.vision.imagegenerator.ImageGenerator.ConditionOptions
import com.google.mediapipe.tasks.vision.imagegenerator.ImageGenerator.ConditionOptions.ConditionType
import com.google.mediapipe.tasks.vision.imagegenerator.ImageGenerator.ConditionOptions.EdgeConditionOptions
import com.google.mediapipe.tasks.vision.imagegenerator.ImageGenerator.ImageGeneratorOptions
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import java.util.concurrent.Executors

/** On-phone Stable Diffusion 1.5 (MediaPipe Image Generator) exposed to Dart. */
class MainActivity : FlutterActivity() {
    private val worker = Executors.newSingleThreadExecutor()
    private val mainHandler = Handler(Looper.getMainLooper())
    private var generator: ImageGenerator? = null
    private var loadedKey: String? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "kira_void/images")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "generate" -> {
                        val dir = call.argument<String>("dir") ?: ""
                        val prompt = call.argument<String>("prompt") ?: ""
                        val steps = call.argument<Int>("steps") ?: 20
                        val seed = call.argument<Int>("seed") ?: 0
                        val image = call.argument<ByteArray>("image")
                        worker.execute {
                            try {
                                val png = generate(dir, prompt, steps, seed, image)
                                mainHandler.post { result.success(png) }
                            } catch (e: Throwable) {
                                mainHandler.post { result.error("generate", e.message ?: e.toString(), null) }
                            }
                        }
                    }
                    "close" -> worker.execute {
                        closeGenerator()
                        mainHandler.post { result.success(null) }
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun generate(dir: String, prompt: String, steps: Int, seed: Int, image: ByteArray?): ByteArray {
        val gen = load(dir, image != null)
        val res = if (image == null) {
            gen.generate(prompt, steps, seed)
        } else {
            // Photo mode: keeps the outlines of the photo and repaints it by the prompt.
            val src = BitmapFactory.decodeByteArray(image, 0, image.size)
            val square = Bitmap.createScaledBitmap(src, 512, 512, true)
            gen.generate(prompt, BitmapImageBuilder(square).build(), ConditionType.EDGE, steps, seed)
        }
        val bitmap = BitmapExtractor.extract(res.generatedImage())
        val out = ByteArrayOutputStream()
        bitmap.compress(Bitmap.CompressFormat.PNG, 100, out)
        return out.toByteArray()
    }

    private fun load(dir: String, edge: Boolean): ImageGenerator {
        val key = "$dir|$edge"
        val current = generator
        if (current != null && loadedKey == key) return current
        closeGenerator()
        val options = ImageGeneratorOptions.builder().setImageGeneratorModelDirectory(dir).build()
        val gen = if (edge) {
            val edgeOptions = EdgeConditionOptions.builder()
                .setThreshold1(100.0f)
                .setThreshold2(100.0f)
                .setApertureSize(3)
                .setL2Gradient(false)
                .setPluginModelBaseOptions(
                    BaseOptions.builder().setModelAssetPath("canny_edge_plugin.tflite").build()
                )
                .build()
            ImageGenerator.createFromOptions(
                this, options, ConditionOptions.builder().setEdgeConditionOptions(edgeOptions).build()
            )
        } else {
            ImageGenerator.createFromOptions(this, options)
        }
        generator = gen
        loadedKey = key
        return gen
    }

    private fun closeGenerator() {
        try {
            generator?.close()
        } catch (e: Throwable) {
            // already closed
        }
        generator = null
        loadedKey = null
    }
}
