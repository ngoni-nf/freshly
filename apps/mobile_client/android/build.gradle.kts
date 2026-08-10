allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

// Flutter's standard out-of-tree build layout: everything lands in ../../build
// rather than inside each module, which keeps the Dart and Gradle outputs in
// one place and makes a clean rebuild a single directory delete.
val newBuildDir: Directory =
    rootProject.layout.buildDirectory.dir("../../build").get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
