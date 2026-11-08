package crm.tasks

import crm.auth.CrmUserDetails
import crm.shared.RowVersion
import crm.shared.getInstant
import crm.shared.getInstantOrNull
import crm.shared.getIntOrNull
import crm.shared.getLocalDate
import crm.shared.getLongOrNull
import crm.shared.getRowVersion
import crm.shared.toUtcLocalDateTime
import io.swagger.v3.oas.annotations.Operation
import io.swagger.v3.oas.annotations.tags.Tag
import jakarta.validation.Valid
import jakarta.validation.constraints.NotBlank
import jakarta.validation.constraints.NotNull
import jakarta.validation.constraints.Pattern
import jakarta.validation.constraints.Size
import org.springframework.format.annotation.DateTimeFormat
import org.springframework.http.HttpStatus
import org.springframework.jdbc.core.RowMapper
import org.springframework.jdbc.core.simple.JdbcClient
import org.springframework.security.core.annotation.AuthenticationPrincipal
import org.springframework.stereotype.Repository
import org.springframework.web.bind.annotation.DeleteMapping
import org.springframework.web.bind.annotation.GetMapping
import org.springframework.web.bind.annotation.PathVariable
import org.springframework.web.bind.annotation.PostMapping
import org.springframework.web.bind.annotation.PutMapping
import org.springframework.web.bind.annotation.RequestBody
import org.springframework.web.bind.annotation.RequestMapping
import org.springframework.web.bind.annotation.RequestParam
import org.springframework.web.bind.annotation.ResponseStatus
import org.springframework.web.bind.annotation.RestController
import java.sql.Types
import java.time.Instant
import java.time.LocalDate

/** A task: who does what from which day to which day (ADR-0014). Days are Warsaw calendar days, both included. */
data class TaskResponse(
    val id: Long,
    val title: String,
    val description: String,
    val assigneeUserId: Int,
    val assigneeName: String,
    val assigneeDepartment: String?,
    val startDate: LocalDate,
    val endDate: LocalDate,
    val done: Boolean,
    val doneAt: Instant?,
    val clientId: Long?,
    val clientName: String?,
    val projectId: Long?,
    val projectName: String?,
    val createdBy: Int,
    val createdByName: String,
    val createdAt: Instant,
    val updatedAt: Instant,
    val rowVersion: String,
    /** The deal the task belongs to (ADR-0017); finishing it logs on the deal. */
    val dealId: Long?,
    val dealTitle: String?,
)

data class TaskRequest(
    @field:NotBlank @field:Size(max = 200) val title: String?,
    @field:Size(max = 2000) val description: String?,
    @field:NotNull val assigneeUserId: Int?,
    @field:NotNull val startDate: LocalDate?,
    @field:NotNull val endDate: LocalDate?,
    val clientId: Long?,
    val projectId: Long?,
    /** A deal the task belongs to; its client becomes the task's client. */
    val dealId: Long? = null,
    /** Required to update; ignored on create. */
    @field:Pattern(regexp = RowVersion.PATTERN) val rowVersion: String?,
)

data class SetDoneRequest(
    @field:NotNull val done: Boolean?,
    @field:NotBlank @field:Pattern(regexp = RowVersion.PATTERN) val rowVersion: String?,
)

data class DepartmentResponse(val name: String, val users: Int)

data class SetDepartmentRequest(@field:Size(max = 50) val department: String?)

data class UserDepartmentResponse(val id: Int, val displayName: String, val department: String?)

/** Tasks and departments (ADR-0014): one `EXEC app.task_*` / `app.department_*` per method. */
@Repository
class TaskRepository(private val jdbc: JdbcClient) {
    private val row = RowMapper { rs, _ ->
        TaskResponse(
            id = rs.getLong("id"),
            title = rs.getString("title"),
            description = rs.getString("description"),
            assigneeUserId = rs.getInt("assignee_user_id"),
            assigneeName = rs.getString("assignee_name"),
            assigneeDepartment = rs.getString("assignee_department"),
            startDate = rs.getLocalDate("start_date"),
            endDate = rs.getLocalDate("end_date"),
            done = rs.getBoolean("is_done"),
            doneAt = rs.getInstantOrNull("done_at"),
            clientId = rs.getLongOrNull("client_id"),
            clientName = rs.getString("client_name"),
            projectId = rs.getLongOrNull("project_id"),
            projectName = rs.getString("project_name"),
            createdBy = rs.getInt("created_by"),
            createdByName = rs.getString("created_by_name"),
            createdAt = rs.getInstant("created_at"),
            updatedAt = rs.getInstant("updated_at"),
            rowVersion = rs.getRowVersion(),
            dealId = rs.getLongOrNull("deal_id"),
            dealTitle = rs.getString("deal_title"),
        )
    }

    fun list(actorId: Int, from: LocalDate, to: LocalDate, scope: String, department: String?, done: Boolean?): List<TaskResponse> =
        jdbc.sql(
            "EXEC app.task_list @actor_id = :actorId, @from = :from, @to = :to, @scope = :scope, " +
                "@department = :department, @done = :done",
        )
            .param("actorId", actorId, Types.INTEGER)
            .param("from", from, Types.DATE)
            .param("to", to, Types.DATE)
            .param("scope", scope, Types.VARCHAR)
            .param("department", department, Types.NVARCHAR)
            .param("done", done, Types.BIT)
            .query(row)
            .list()

    fun agenda(actorId: Int, until: LocalDate, doneSince: Instant?): List<TaskResponse> =
        jdbc.sql("EXEC app.task_agenda @actor_id = :actorId, @until = :until, @done_since = :doneSince")
            .param("actorId", actorId, Types.INTEGER)
            .param("until", until, Types.DATE)
            .param("doneSince", doneSince?.toUtcLocalDateTime(), Types.TIMESTAMP)
            .query(row)
            .list()

    fun get(actorId: Int, id: Long): TaskResponse =
        jdbc.sql("EXEC app.task_get @actor_id = :actorId, @task_id = :id")
            .param("actorId", actorId, Types.INTEGER).param("id", id, Types.BIGINT).query(row).single()

    fun create(actorId: Int, body: TaskRequest): TaskResponse =
        jdbc.sql(
            "EXEC app.task_create @actor_id = :actorId, @title = :title, @description = :description, " +
                "@assignee_user_id = :assignee, @start_date = :start, @end_date = :end, @client_id = :clientId, " +
                "@project_id = :projectId, @deal_id = :dealId",
        )
            .param("actorId", actorId, Types.INTEGER)
            .fields(body)
            .query(row)
            .single()

    fun update(actorId: Int, id: Long, body: TaskRequest): TaskResponse =
        jdbc.sql(
            "EXEC app.task_update @actor_id = :actorId, @task_id = :id, @title = :title, @description = :description, " +
                "@assignee_user_id = :assignee, @start_date = :start, @end_date = :end, @client_id = :clientId, " +
                "@project_id = :projectId, @row_version = :rowVersion, @deal_id = :dealId",
        )
            .param("actorId", actorId, Types.INTEGER)
            .param("id", id, Types.BIGINT)
            .fields(body)
            .param("rowVersion", body.rowVersion?.let(RowVersion::parse), Types.BINARY)
            .query(row)
            .single()

    private fun JdbcClient.StatementSpec.fields(body: TaskRequest) = this
        .param("title", body.title, Types.NVARCHAR)
        .param("description", body.description, Types.NVARCHAR)
        .param("assignee", body.assigneeUserId, Types.INTEGER)
        .param("start", body.startDate, Types.DATE)
        .param("end", body.endDate, Types.DATE)
        .param("clientId", body.clientId, Types.BIGINT)
        .param("projectId", body.projectId, Types.BIGINT)
        .param("dealId", body.dealId, Types.BIGINT)

    fun setDone(actorId: Int, id: Long, done: Boolean, rowVersion: String): TaskResponse =
        jdbc.sql("EXEC app.task_set_done @actor_id = :actorId, @task_id = :id, @done = :done, @row_version = :rowVersion")
            .param("actorId", actorId, Types.INTEGER)
            .param("id", id, Types.BIGINT)
            .param("done", done, Types.BIT)
            .param("rowVersion", RowVersion.parse(rowVersion), Types.BINARY)
            .query(row)
            .single()

    fun delete(actorId: Int, id: Long, rowVersion: String) {
        jdbc.sql("EXEC app.task_delete @actor_id = :actorId, @task_id = :id, @row_version = :rowVersion")
            .param("actorId", actorId, Types.INTEGER)
            .param("id", id, Types.BIGINT)
            .param("rowVersion", RowVersion.parse(rowVersion), Types.BINARY)
            .update()
    }

    fun departments(actorId: Int): List<DepartmentResponse> =
        jdbc.sql("EXEC app.department_list @actor_id = :actorId")
            .param("actorId", actorId, Types.INTEGER)
            .query { rs, _ -> DepartmentResponse(rs.getString("name"), rs.getInt("users")) }
            .list()

    fun setDepartment(actorId: Int, userId: Int, department: String?): UserDepartmentResponse =
        jdbc.sql("EXEC app.user_set_department @actor_id = :actorId, @user_id = :userId, @department = :department")
            .param("actorId", actorId, Types.INTEGER)
            .param("userId", userId, Types.INTEGER)
            .param("department", department, Types.NVARCHAR)
            .query { rs, _ -> UserDepartmentResponse(rs.getInt("id"), rs.getString("display_name"), rs.getString("department")) }
            .single()
}

/** Tasks on the calendar and the timeline (ADR-0014); every user sees every task, the procedures decide who edits. */
@Tag(name = "Tasks")
@RestController
@RequestMapping("/api")
class TaskController(private val tasks: TaskRepository) {

    @Operation(
        summary = "Tasks overlapping from..to (at most 120 days). scope MINE, DEPARTMENT (mine, or `department`) or ALL; " +
            "done: true / false / all.",
    )
    @GetMapping("/tasks")
    fun listTasks(
        @AuthenticationPrincipal actor: CrmUserDetails,
        @RequestParam @DateTimeFormat(iso = DateTimeFormat.ISO.DATE) from: LocalDate,
        @RequestParam @DateTimeFormat(iso = DateTimeFormat.ISO.DATE) to: LocalDate,
        @RequestParam(defaultValue = "ALL") scope: String,
        @RequestParam(required = false) department: String?,
        @RequestParam(required = false) done: Boolean?,
    ): List<TaskResponse> = tasks.list(actor.id, from, to, scope, department, done)

    @Operation(
        summary = "My agenda: my open tasks started by `until` (overdue first, by their last day) and the ones I " +
            "finished since `doneSince`.",
    )
    @GetMapping("/tasks/agenda")
    fun taskAgenda(
        @AuthenticationPrincipal actor: CrmUserDetails,
        @RequestParam @DateTimeFormat(iso = DateTimeFormat.ISO.DATE) until: LocalDate,
        @RequestParam(required = false) doneSince: Instant?,
    ): List<TaskResponse> = tasks.agenda(actor.id, until, doneSince)

    @Operation(summary = "Task details.")
    @GetMapping("/tasks/{id}")
    fun getTask(@AuthenticationPrincipal actor: CrmUserDetails, @PathVariable id: Long): TaskResponse = tasks.get(actor.id, id)

    @Operation(summary = "Plan a task for anyone.")
    @PostMapping("/tasks")
    @ResponseStatus(HttpStatus.CREATED)
    fun createTask(@AuthenticationPrincipal actor: CrmUserDetails, @Valid @RequestBody body: TaskRequest): TaskResponse =
        tasks.create(actor.id, body)

    @Operation(summary = "Change a task, also its dates (author, assignee, manager, admin). rowVersion required.")
    @PutMapping("/tasks/{id}")
    fun updateTask(
        @AuthenticationPrincipal actor: CrmUserDetails,
        @PathVariable id: Long,
        @Valid @RequestBody body: TaskRequest,
    ): TaskResponse = tasks.update(actor.id, id, body)

    @Operation(summary = "Mark a task done or open again.")
    @PostMapping("/tasks/{id}/done")
    fun setTaskDone(
        @AuthenticationPrincipal actor: CrmUserDetails,
        @PathVariable id: Long,
        @Valid @RequestBody body: SetDoneRequest,
    ): TaskResponse = tasks.setDone(actor.id, id, body.done!!, body.rowVersion!!)

    @Operation(summary = "Delete a task.")
    @DeleteMapping("/tasks/{id}")
    @ResponseStatus(HttpStatus.NO_CONTENT)
    fun deleteTask(
        @AuthenticationPrincipal actor: CrmUserDetails,
        @PathVariable id: Long,
        @RequestParam @Pattern(regexp = RowVersion.PATTERN) rowVersion: String,
    ) = tasks.delete(actor.id, id, rowVersion)

    @Operation(summary = "Departments with their active users.")
    @GetMapping("/departments")
    fun listDepartments(@AuthenticationPrincipal actor: CrmUserDetails): List<DepartmentResponse> = tasks.departments(actor.id)

    @Operation(summary = "Set a user's department (ADMIN); empty takes it off.")
    @PutMapping("/users/{id}/department")
    fun setUserDepartment(
        @AuthenticationPrincipal actor: CrmUserDetails,
        @PathVariable id: Int,
        @Valid @RequestBody body: SetDepartmentRequest,
    ): UserDepartmentResponse = tasks.setDepartment(actor.id, id, body.department)
}
