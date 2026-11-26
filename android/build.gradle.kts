// SPDX-License-Identifier: GPL-3.0-or-later
group = "ch.rosenweg4303.basis"
version = "0.1.0"

buildscript {
    val kotlinVersion = "2.4.0"
    repositories {
        google()
        mavenCentral()
    }

    dependencies {
        classpath("com.android.tools.build:gradle:9.1.0")
        classpath("org.jetbrains.kotlin:kotlin-gradle-plugin:$kotlinVersion")
    }
}

allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

// commons-rosenweg (Anmeldeschirm, Rosenweg-Anmeldung, Karten-Sitzung) liegt wie fuer die
// Kotlin-Apps im lokalen Maven-Repository (commons-rosenweg: ./gradlew publishToMavenLocal).
// Die App loest die Abhaengigkeiten des Plugins mit ihren eigenen Repositories auf: darum
// rootProject, beschraenkt auf ch.rosenweg4303.
rootProject.allprojects {
    repositories {
        mavenLocal {
            content { includeGroup("ch.rosenweg4303") }
        }
    }
}

plugins {
    id("com.android.library")
}

android {
    namespace = "ch.rosenweg4303.basis"

    compileSdk = 36

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    sourceSets {
        getByName("main") {
            java.srcDirs("src/main/kotlin")
        }
    }

    defaultConfig {
        minSdk = 26   // commons-rosenweg (cloud) verlangt 26
    }

}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

dependencies {
    // Anmeldeschirm (Karte oder Rosenweg-Konto), Rosenweg-Anmeldung und Karten-Sitzung -
    // derselbe Code wie in den Kotlin-Apps und (Aussehen/Kartenleser) in Rosenweg Geraet
    implementation("ch.rosenweg4303:cloud:0.9.0")
}
