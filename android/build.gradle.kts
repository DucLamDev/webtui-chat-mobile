import com.android.build.gradle.LibraryExtension
import org.jetbrains.kotlin.gradle.dsl.JvmTarget
import org.jetbrains.kotlin.gradle.tasks.KotlinCompile

allprojects {
    repositories {
        google()
        mavenCentral()
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
subprojects {
    if (name == "receive_sharing_intent") {
        plugins.withId("com.android.library") {
            extensions.configure<LibraryExtension>("android") {
                compileOptions {
                    sourceCompatibility = JavaVersion.VERSION_17
                    targetCompatibility = JavaVersion.VERSION_17
                }
            }
        }
        tasks.withType<KotlinCompile>().configureEach {
            compilerOptions.jvmTarget.set(JvmTarget.JVM_17)
        }
    }
}

// opus_flutter_android 3.x (giải mã ghi âm WebM / Ogg) tự dịch libopus bằng ndkBuild nhưng không khai ndkVersion, nên
// Gradle dùng NDK 27 mặc định: libopus.so chỉ căn lề 4 KB, không qua kiểm 16 KB (check_android_elf_alignment, Google Play
// cho Android 15+). Dịch bằng đúng NDK của app (mặc định của Flutter, NDK r28+ tự căn lề 16 KB). Còn minSdkVersion 19
// của thư viện thì xử lý ở gradle.properties (android.ndk.suppressMinSdkVersionError).
subprojects {
    if (name == "opus_flutter_android") {
        plugins.withId("com.android.library") {
            val appNdkVersion =
                rootProject
                    .project(":app")
                    .extensions
                    .getByType<com.android.build.api.dsl.ApplicationExtension>()
                    .ndkVersion
            extensions.configure<LibraryExtension>("android") {
                if (!appNdkVersion.isNullOrBlank()) {
                    ndkVersion = appNdkVersion
                }
            }
        }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
