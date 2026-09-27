allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

// whisper_ggml 自带的 ffmpeg_kit_flutter_new_min AAR 要求 compileSdk >= 35，
// 而该插件自身编译目标是 android-34：这里把低于 35 的子项目 compileSdk 统一
// 抬到 35，避免 checkDebugAarMetadata 失败（compileSdk 只影响编译期 API，
// 与 targetSdk/minSdk 的运行时语义无关）。
subprojects {
    afterEvaluate {
        val androidExtension = project.extensions.findByName("android")
            as? com.android.build.gradle.BaseExtension ?: return@afterEvaluate
        val required = 35
        val current = androidExtension.compileSdkVersion
            ?.removePrefix("android-")?.toIntOrNull() ?: return@afterEvaluate
        if (current < required) {
            androidExtension.compileSdkVersion(required)
        }
    }
}

val newBuildDir: Directory =
    rootProject.layout.buildDirectory
        .dir("../../build")
        .get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}
subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
