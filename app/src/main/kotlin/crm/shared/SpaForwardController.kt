package crm.shared

import org.springframework.stereotype.Controller
import org.springframework.web.bind.annotation.GetMapping

/**
 * The React app (resources/static, built by frontend/build-to-resources.sh) routes in the browser. A reload or
 * a link to /clients/42 must return index.html, not 404. Paths with a dot are files (assets) and paths of the
 * API, Actuator and OpenAPI are left alone, so an unknown API path is still a 404.
 */
@Controller
class SpaForwardController {
    @GetMapping(
        "/",
        "/{first:(?!api$|actuator$|v3$|swagger-ui$)[^.]*}",
        "/{first:(?!api$|actuator$|v3$|swagger-ui$)[^.]*}/{second:[^.]*}",
        "/{first:(?!api$|actuator$|v3$|swagger-ui$)[^.]*}/{second:[^.]*}/{third:[^.]*}",
    )
    fun index(): String = "forward:/index.html"
}
