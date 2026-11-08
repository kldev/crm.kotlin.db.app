import org.springframework.boot.gradle.plugin.SpringBootPlugin

plugins {
    alias(libs.plugins.kotlin.jvm)
    alias(libs.plugins.kotlin.spring)
    alias(libs.plugins.spring.boot)
}

kotlin {
    jvmToolchain(25)
    compilerOptions {
        freeCompilerArgs.addAll("-Xjsr305=strict")
    }
}

dependencies {
    implementation(platform(SpringBootPlugin.BOM_COORDINATES))

    implementation("org.springframework.boot:spring-boot-starter-webmvc")
    implementation("org.springframework.boot:spring-boot-starter-validation")
    implementation("org.springframework.boot:spring-boot-starter-actuator")
    implementation("org.springframework.boot:spring-boot-starter-security")
    // Plain JDBC only: every call is `EXEC <schema>.<procedure>` through JdbcClient (ADR-0002).
    implementation("org.springframework.boot:spring-boot-starter-jdbc")
    // Flyway runs only in CRM_MODE=migrate (and in tests), with the migrator login.
    implementation("org.springframework.boot:spring-boot-starter-flyway")
    implementation("org.flywaydb:flyway-sqlserver")
    implementation(libs.springdoc.webmvc.ui)
    // Desk attachments in S3 (RustFS locally, ADR-0009). The JDK HTTP client only: no Netty, no Apache client.
    implementation(platform(libs.aws.sdk.bom))
    implementation("software.amazon.awssdk:s3") {
        exclude(group = "software.amazon.awssdk", module = "netty-nio-client")
        exclude(group = "software.amazon.awssdk", module = "apache-client")
    }
    implementation("software.amazon.awssdk:url-connection-client")
    implementation("tools.jackson.module:jackson-module-kotlin")
    implementation("org.jetbrains.kotlin:kotlin-reflect")
    runtimeOnly("com.microsoft.sqlserver:mssql-jdbc")

    testImplementation("org.springframework.boot:spring-boot-starter-test")
    testImplementation("org.springframework.boot:spring-boot-testcontainers")
    testImplementation("org.testcontainers:testcontainers-junit-jupiter")
    testImplementation("org.testcontainers:testcontainers-mssqlserver")
    testImplementation("com.microsoft.sqlserver:mssql-jdbc")
    testImplementation("org.jetbrains.kotlin:kotlin-test-junit5")
    testRuntimeOnly("org.junit.platform:junit-platform-launcher")
}

tasks.bootJar {
    archiveFileName = "app.jar"
}

tasks.jar {
    enabled = false
}

tasks.test {
    useJUnitPlatform()
    // SQL Server in Testcontainers takes a while to start; one container is shared by all test classes.
    systemProperty("junit.jupiter.execution.timeout.default", "5m")
}

// ADR-0002: no ORM and no query mapper may ever reach the classpath. `check` (and so `build`) fails if one does.
val forbiddenDependencies = listOf(
    "jakarta.persistence",
    "org.hibernate.orm", // hibernate-validator (Bean Validation) is allowed, the ORM is not
    "org.hibernate:hibernate-core",
    "org.springframework.data:spring-data-jpa",
    "org.springframework.data:spring-data-jdbc",
    "org.springframework.data:spring-data-relational",
    "org.jooq",
    "org.jetbrains.exposed",
    "org.mybatis",
    "org.eclipse.persistence",
)

val verifyNoOrm by tasks.registering {
    group = "verification"
    description = "Fails when an ORM or query mapper is on the runtime or test classpath (ADR-0002)."
    val runtime = configurations.runtimeClasspath
    val test = configurations.testRuntimeClasspath
    inputs.files(runtime, test)
    doLast {
        val modules = (runtime.get().incoming.resolutionResult.allComponents +
            test.get().incoming.resolutionResult.allComponents)
            .mapNotNull { it.moduleVersion }
            .map { "${it.group}:${it.name}" }
            .toSortedSet()
        val found = modules.filter { module -> forbiddenDependencies.any { module.startsWith(it) } }
        if (found.isNotEmpty()) {
            throw GradleException(
                "Forbidden ORM/query-mapper dependencies on the classpath (ADR-0002): ${found.joinToString()}",
            )
        }
    }
}

tasks.check {
    dependsOn(verifyNoOrm)
}
