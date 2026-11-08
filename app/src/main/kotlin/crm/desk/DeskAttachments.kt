package crm.desk

import crm.storage.AttachmentStorage
import org.slf4j.LoggerFactory
import org.springframework.stereotype.Service
import org.springframework.web.multipart.MultipartFile
import tools.jackson.databind.json.JsonMapper
import java.util.UUID

/**
 * Desk attachments (ADR-0009), in this order: the procedure checks each file (name, type by extension, size), the bytes
 * go to the bucket, then the procedure records them as events in one transaction - checking the rules again under the
 * ticket's lock. When the database refuses, the stored bytes are deleted again; a crash between the two steps leaves an
 * orphan object, never an event pointing at nothing. The rules are the procedures'; this class only orders the steps.
 */
@Service
class DeskAttachments(
    private val desk: DeskRepository,
    private val storage: AttachmentStorage,
    private val json: JsonMapper,
) {
    private val log = LoggerFactory.getLogger(javaClass)

    fun attach(actorId: Int, ticketId: Long, files: List<MultipartFile>): TicketResponse =
        withStored(files) { desk.attach(actorId, ticketId, it) }

    fun reportPublic(body: PublicReportRequest, files: List<MultipartFile>): PublicReportResponse =
        if (files.isEmpty()) desk.reportPublic(body, null) else withStored(files) { desk.reportPublic(body, it) }

    private fun <T> withStored(files: List<MultipartFile>, record: (String) -> T): T {
        val nonEmpty = files.filterNot { it.originalFilename.isNullOrBlank() && it.isEmpty }
        // Checked before any byte is stored, so a refused file costs no upload.
        val checked = nonEmpty.map { it to desk.checkAttachment(it.originalFilename, it.size) }
        val stored = mutableListOf<StoredFile>()
        try {
            for ((file, check) in checked) {
                val id = UUID.randomUUID()
                val key = "attachments/$id"
                file.inputStream.use { storage.put(key, it, file.size, check.contentType) }
                stored += StoredFile(id, file.originalFilename ?: check.fileName, file.size, key)
            }
            return record(json.writeValueAsString(stored))
        } catch (error: Exception) {
            cleanUp(stored)
            throw error
        }
    }

    private fun cleanUp(stored: List<StoredFile>) {
        try {
            storage.delete(stored.map { it.storageKey })
        } catch (error: Exception) {
            log.warn("Could not delete {} refused attachment object(s); they stay as orphans", stored.size, error)
        }
    }
}
