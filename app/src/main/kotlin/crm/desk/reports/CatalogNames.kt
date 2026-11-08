package crm.desk.reports

import org.springframework.stereotype.Component
import tools.jackson.databind.json.JsonMapper

/**
 * English names of the desk catalog for exports (ADR-0008): categories, subcategories, markets, departments, report
 * fields and their choices, keyed by the Polish name stored in the database. Generated from Halcyon's catalog, the
 * same data as the web app's catalogEn.ts; a name missing here stays Polish.
 */
@Component
class CatalogNames(json: JsonMapper) {
    private val english: Map<String, String> = javaClass.getResourceAsStream("/desk/catalog-en.json")!!.use { stream ->
        json.readValue(stream, json.typeFactory.constructMapType(Map::class.java, String::class.java, String::class.java))
    }

    fun n(name: String?, lang: Lang): String = when {
        name == null -> ""
        lang == Lang.EN -> english[name] ?: name
        else -> name
    }
}
