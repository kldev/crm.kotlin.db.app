package crm.storage

import org.springframework.stereotype.Component
import software.amazon.awssdk.auth.credentials.AwsBasicCredentials
import software.amazon.awssdk.auth.credentials.StaticCredentialsProvider
import software.amazon.awssdk.core.ResponseInputStream
import software.amazon.awssdk.core.checksums.RequestChecksumCalculation
import software.amazon.awssdk.core.checksums.ResponseChecksumValidation
import software.amazon.awssdk.core.sync.RequestBody
import software.amazon.awssdk.http.urlconnection.UrlConnectionHttpClient
import software.amazon.awssdk.regions.Region
import software.amazon.awssdk.services.s3.S3Client
import software.amazon.awssdk.services.s3.model.Delete
import software.amazon.awssdk.services.s3.model.GetObjectResponse
import software.amazon.awssdk.services.s3.model.ObjectIdentifier
import java.io.InputStream
import java.net.URI
import java.time.Duration

/**
 * The bytes of desk attachments in a private S3 bucket (ADR-0009). Path-style URLs and checksums only when an
 * operation requires them: the SDK's default CRC32 trailers are not understood by every S3-compatible server (RustFS).
 */
@Component
class AttachmentStorage(private val properties: StorageProperties) : AutoCloseable {
    private val s3: S3Client = S3Client.builder()
        .endpointOverride(URI.create(properties.endpoint))
        .region(Region.of(properties.region))
        .forcePathStyle(true)
        .requestChecksumCalculation(RequestChecksumCalculation.WHEN_REQUIRED)
        .responseChecksumValidation(ResponseChecksumValidation.WHEN_REQUIRED)
        .credentialsProvider(
            StaticCredentialsProvider.create(AwsBasicCredentials.create(properties.accessKey, properties.secretKey)),
        )
        .httpClient(
            UrlConnectionHttpClient.builder()
                .connectionTimeout(Duration.ofSeconds(3))
                .socketTimeout(Duration.ofSeconds(60))
                .build(),
        )
        .build()

    fun put(key: String, content: InputStream, size: Long, contentType: String) {
        s3.putObject({ it.bucket(properties.bucket).key(key).contentType(contentType).contentLength(size) },
            RequestBody.fromInputStream(content, size))
    }

    fun open(key: String): ResponseInputStream<GetObjectResponse> =
        s3.getObject { it.bucket(properties.bucket).key(key) }

    /** Removes objects the database refused to record. Best effort: an orphan object is harmless, a lost event is not. */
    fun delete(keys: Collection<String>) {
        if (keys.isEmpty()) return
        s3.deleteObjects {
            it.bucket(properties.bucket).delete(Delete.builder().objects(keys.map { k -> ObjectIdentifier.builder().key(k).build() }).build())
        }
    }

    /** Readiness: the bucket answers with these keys. */
    fun ping() {
        s3.headBucket { it.bucket(properties.bucket) }
    }

    override fun close() = s3.close()
}
