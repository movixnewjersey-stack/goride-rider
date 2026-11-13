allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

// ---------------------------------------------------------------------
// DIAGNOSTICO firebase_messaging 14.7.10 / compileSdk 33: ese paquete
// trae su propio android/build.gradle interno con compileSdkVersion 33
// fijo. Este bloque fuerza compileSdk 36 a TODOS los subproyectos
// (todos los plugins), sin tocar ninguna version de dependencia.
//
// CORRECCION (error real: "Cannot run Project.afterEvaluate(Action)
// when the project is already evaluated"): movido a ser el PRIMER
// subprojects{} del archivo (antes del bloque de evaluationDependsOn,
// que puede disparar evaluacion temprana de algunos subproyectos), y
// con guardia defensiva: si el subproyecto YA fue evaluado para
// cuando este bloque corre, aplica el cambio directo; si no, lo
// difiere con afterEvaluate como antes. Cubre ambos casos sin
// depender del orden exacto en que Gradle procese cada plugin.
// ---------------------------------------------------------------------
subprojects {
    fun applyCompileSdkFix() {
        extensions.findByName("android")?.let { androidExt ->
            val android = androidExt as com.android.build.gradle.BaseExtension
            if (android.compileSdkVersion != "android-36") {
                android.compileSdkVersion(36)
            }
        }
    }

    if (project.state.executed) {
        applyCompileSdkFix()
    } else {
        afterEvaluate {
            applyCompileSdkFix()
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
