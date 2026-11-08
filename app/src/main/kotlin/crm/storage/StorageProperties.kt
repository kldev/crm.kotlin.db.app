package crm.storage

import jakarta.validation.constraints.NotBlank
import org.springframework.boot.context.properties.ConfigurationProperties
import org.springframework.validation.annotation.Validated

/**
 * The attachments bucket (ADR-0009), env only: CRM_S3_ENDPOINT, CRM_S3_REGION, CRM_S3_ACCESS_KEY, CRM_S3_SECRET_KEY,
 * CRM_S3_BUCKET. The bucket is private and created by the deployment (rustfs-init locally), never by the app.
 */
@Validated
@ConfigurationProperties("crm.storage")
data class StorageProperties(
    @field:NotBlank val endpoint: String = "http://localhost:9000",
    @field:NotBlank val region: String = "us-east-1",
    val accessKey: String = "",
    val secretKey: String = "",
    @field:NotBlank val bucket: String = "crm-attachments",
)
