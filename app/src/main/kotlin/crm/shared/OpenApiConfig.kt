package crm.shared

import org.springdoc.core.customizers.OpenApiCustomizer
import org.springframework.context.annotation.Bean
import org.springframework.context.annotation.Configuration

/**
 * springdoc marks Kotlin nullable properties as nullable but does not mark the others as required, so a generated
 * client would see every field as optional. A property that is not nullable is always present in a response:
 * mark it required. Request bodies use nullable fields with Bean Validation, so they stay optional.
 */
@Configuration
class OpenApiConfig {
    @Bean
    fun requiredNonNullableProperties(): OpenApiCustomizer = OpenApiCustomizer { api ->
        api.components?.schemas?.values?.forEach { schema ->
            val properties = schema.properties ?: return@forEach
            val required = properties
                .filter { (_, property) -> property.nullable != true && property.types?.contains("null") != true }
                .keys
                .sorted()
            if (required.isNotEmpty()) schema.required = required
        }
    }
}
