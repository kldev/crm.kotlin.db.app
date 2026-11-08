// Plugins are declared once here and applied only by the projects that need them.
plugins {
    alias(libs.plugins.kotlin.jvm) apply false
    alias(libs.plugins.kotlin.spring) apply false
    alias(libs.plugins.spring.boot) apply false
}

allprojects {
    group = "crm"
    version = "0.1.0-SNAPSHOT"

    repositories {
        mavenCentral()
    }
}
