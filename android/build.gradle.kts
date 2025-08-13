allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

val newBuildDir: Directory = rootProject.layout.buildDirectory.dir("../../build").get()
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

plugins {
    // ✅ OneSignal Gradle Plugin
    id("com.onesignal.androidsdk.onesignal-gradle-plugin") version "0.14.0" apply false

    // ✅ Google Services Plugin
    id("com.google.gms.google-services") version "4.4.3" apply false
}
