import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val releaseKeyPropertiesFile: File = rootProject.file("key.properties")
val releaseKeyProperties = Properties().apply {
    if (releaseKeyPropertiesFile.isFile) {
        load(releaseKeyPropertiesFile.readText(Charsets.UTF_8).removePrefix("\uFEFF").reader())
    }
}
val releaseSigningKeys = listOf("storeFile", "storePassword", "keyAlias", "keyPassword")
val releaseSigningValue = { key: String -> releaseKeyProperties.getProperty(key)?.takeIf { it.isNotBlank() } }
val releaseStoreFile: File? = releaseSigningValue("storeFile")?.let { file(it) }
val releaseSigningProblem: String? = when {
    !releaseKeyPropertiesFile.isFile ->
        "Release signing is not configured: ${releaseKeyPropertiesFile.absolutePath} not found. " +
            "Create it with ${releaseSigningKeys.joinToString(", ")} as described in README.md " +
            "(section \"Подпись release-сборки\"). Debug and profile builds do not need it."
    releaseSigningKeys.any { releaseSigningValue(it) == null } ->
        "Release signing: ${releaseKeyPropertiesFile.absolutePath} has no value for " +
            "${releaseSigningKeys.filter { releaseSigningValue(it) == null }.joinToString(", ")}. " +
            "Required keys: ${releaseSigningKeys.joinToString(", ")}."
    releaseStoreFile?.isFile != true ->
        "Release signing: keystore file not found: ${releaseStoreFile?.absolutePath} " +
            "(storeFile in ${releaseKeyPropertiesFile.absolutePath}). " +
            "Use an absolute path with forward slashes, for example storeFile=C:/Users/<name>/keys/milionchik-upload.jks."
    else -> null
}

android {
    namespace = "ru.milionchik.app"
    // targetSdk/compileSdk 36 — значение шаблона Flutter 3.47.7; Google Play с 31.08.2026
    // требует не ниже 36. API 37 требует AGP >= 9.1.1 (в шаблоне 9.1.0) — пересмотреть на этапе 15.
    compileSdk = 36
    ndkVersion = flutter.ndkVersion

    compileOptions {
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // Не меняется после публикации в Google Play.
        applicationId = "ru.milionchik.app"
        minSdk = 30 // Android 11
        targetSdk = 36
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        create("release") {
            storeFile = releaseStoreFile
            storePassword = releaseSigningValue("storePassword")
            keyAlias = releaseSigningValue("keyAlias")
            keyPassword = releaseSigningValue("keyPassword")
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("release")
        }
    }
}

val checkReleaseSigning = tasks.register("checkReleaseSigning") {
    val problem = releaseSigningProblem
    val summary = "[signing] release signing from ${releaseKeyPropertiesFile.absolutePath}: " +
        "storeFile=${releaseStoreFile?.absolutePath} keyAlias=${releaseSigningValue("keyAlias")}"
    doLast {
        if (problem != null) {
            throw GradleException(problem)
        }
        logger.quiet(summary)
    }
}

tasks.matching { it.name == "preReleaseBuild" || it.name == "validateSigningRelease" }.configureEach {
    dependsOn(checkReleaseSigning)
}

tasks.matching { it.name.contains("Release") && it.name != checkReleaseSigning.name }.configureEach {
    mustRunAfter(checkReleaseSigning)
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.5")
}
