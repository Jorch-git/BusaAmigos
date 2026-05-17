import org.jetbrains.kotlin.gradle.tasks.KotlinCompile
import org.gradle.api.JavaVersion

allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

subprojects {
    afterEvaluate {
        val androidExt = project.extensions.findByName("android")
        if (androidExt != null) {
            val getNamespaceMethod = androidExt.javaClass.methods.find { it.name == "getNamespace" }
            if (getNamespaceMethod != null) {
                val ns = getNamespaceMethod.invoke(androidExt)
                if (ns == null || ns.toString().isEmpty()) {
                    val setNamespaceMethod = androidExt.javaClass.methods.find { it.name == "setNamespace" }
                    if (setNamespaceMethod != null) {
                        setNamespaceMethod.invoke(androidExt, project.group.toString())
                    }
                }
            }
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
