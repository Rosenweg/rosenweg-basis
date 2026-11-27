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

// commons-rosenweg (Anmeldeschirm, Rosenweg-Anmeldung, Karten-Sitzung) kommt wie fuer die
// Kotlin-Apps aus GitHub Packages, sonst aus dem lokalen Maven-Repository (publishToMavenLocal).
// Die App loest die Abhaengigkeiten des Plugins mit ihren eigenen Repositories auf: darum
// rootProject, beschraenkt auf ch.rosenweg4303.
val gprUser = (findProperty("gpr.user") ?: System.getenv("GITHUB_ACTOR"))?.toString()
val gprKey = (findProperty("gpr.key") ?: System.getenv("GPR_TOKEN") ?: System.getenv("GITHUB_TOKEN"))?.toString()
rootProject.allprojects {
    repositories {
        // GitHub Packages (commons-rosenweg, Workflow pakete.yml); Anmeldedaten lokal aus
        // ~/.gradle/gradle.properties (gpr.user/gpr.key), in Actions GPR_TOKEN oder GITHUB_TOKEN
        if (gprUser != null && gprKey != null) {
            maven {
                name = "RosenwegCommons"
                url = uri("https://maven.pkg.github.com/Rosenweg/commons-rosenweg")
                credentials {
                    username = gprUser
                    password = gprKey
                }
                content { includeGroup("ch.rosenweg4303") }
            }
        }
        // Rueckfall: publishToMavenLocal
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
    // Anmeldeschirm (Karte, Rosenweg-Konto oder QR-Code), Rosenweg-Anmeldung und Karten-Sitzung -
    // derselbe Code wie in den Kotlin-Apps und (Aussehen/Kartenleser) in Rosenweg Geraet.
    // Ab 0.12.0 "QR-Code scannen": bringt CAMERA (gefragt erst beim Tippen, Kamera nicht Pflicht).
    implementation("ch.rosenweg4303:cloud:0.13.8")
    // Rosenweg Updater ausdruecklich (cloud bringt dieselbe Fassung mit): ab 0.1.4 kennt er
    // ch.rosenweg4303.vm/.salz/.profil, ab 0.1.5 plant er erst nach WorkManager ein (vorher
    // "Start: IllegalStateException"), ab 0.1.6 "Nach Updates suchen" (jetztPruefen) und eigene
    // Meldungsnummer. Startet von selbst (ContentProvider UpdaterStart).
    implementation("ch.rosenweg4303:updater:0.1.8")
}
