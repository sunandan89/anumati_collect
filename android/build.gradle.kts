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
// frappe_mobile_sdk still compiles against android-34, but its own
// dependencies (androidx.core 1.18, connectivity_plus, ...) need 36. Raise
// plugin libraries to at least 36; minSdk and targetSdk are untouched.
subprojects {
    afterEvaluate {
        if (plugins.hasPlugin("com.android.library")) {
            val android = extensions.getByName("android")
            val current = android.withGroovyBuilder { "getCompileSdk"() } as Int?
            if (current == null || current < 36) {
                android.withGroovyBuilder { "setCompileSdk"(36) }
            }
        }
    }
}
subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
