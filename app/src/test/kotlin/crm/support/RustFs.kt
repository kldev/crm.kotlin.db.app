package crm.support

import org.testcontainers.containers.GenericContainer
import org.testcontainers.containers.wait.strategy.Wait
import software.amazon.awssdk.auth.credentials.AwsBasicCredentials
import software.amazon.awssdk.auth.credentials.StaticCredentialsProvider
import software.amazon.awssdk.core.checksums.RequestChecksumCalculation
import software.amazon.awssdk.core.checksums.ResponseChecksumValidation
import software.amazon.awssdk.http.urlconnection.UrlConnectionHttpClient
import software.amazon.awssdk.regions.Region
import software.amazon.awssdk.services.s3.S3Client
import java.net.URI
import java.time.Duration

/** One RustFS container for the whole test run - the image of docker compose - with the attachments bucket. */
object RustFs {
    const val ACCESS_KEY = "crmtestkey"
    const val SECRET_KEY = "crm-test-secret-key-0123456789"
    const val BUCKET = "crm-attachments"

    private val container: GenericContainer<*> by lazy {
        GenericContainer("rustfs/rustfs:1.0.0")
            .withEnv("RUSTFS_ACCESS_KEY", ACCESS_KEY)
            .withEnv("RUSTFS_SECRET_KEY", SECRET_KEY)
            .withEnv("RUSTFS_VOLUMES", "/data")
            .withEnv("RUSTFS_ADDRESS", ":9000")
            .withExposedPorts(9000)
            .waitingFor(Wait.forHttp("/health").forPort(9000).withStartupTimeout(Duration.ofMinutes(2)))
            .also {
                it.start()
                client("http://${it.host}:${it.getMappedPort(9000)}").use { s3 -> s3.createBucket { b -> b.bucket(BUCKET) } }
            }
    }

    val endpoint: String
        get() = "http://${container.host}:${container.getMappedPort(9000)}"

    fun client(at: String = endpoint): S3Client = S3Client.builder()
        .endpointOverride(URI.create(at))
        .region(Region.US_EAST_1)
        .forcePathStyle(true)
        .requestChecksumCalculation(RequestChecksumCalculation.WHEN_REQUIRED)
        .responseChecksumValidation(ResponseChecksumValidation.WHEN_REQUIRED)
        .credentialsProvider(StaticCredentialsProvider.create(AwsBasicCredentials.create(ACCESS_KEY, SECRET_KEY)))
        .httpClient(UrlConnectionHttpClient.create())
        .build()

    /** Keys of every object in the bucket (tests check that refused uploads are deleted again). */
    fun keys(): Set<String> = client().use { s3 ->
        s3.listObjectsV2Paginator { it.bucket(BUCKET) }.contents().map { it.key() }.toSet()
    }
}
