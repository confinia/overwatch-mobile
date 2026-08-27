package io.confinia.overwatch

import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.doubleOrNull
import kotlinx.serialization.json.intOrNull
import java.net.HttpURLConnection
import java.net.URL
import java.net.URLEncoder

/**
 * Client for the Overwatch open-data API (`/api/v1`) — read-only, no account.
 * Same idiom as ecobuilding: HttpURLConnection + kotlinx JSON, no HTTP stack
 * dependency for two GET endpoints.
 */
data class Station(val observer: String, val frames: Int, val satellites: Int)
data class Day(val day: String, val frames: Int, val passes: Int, val hitRate: Double?)
data class Pass(val norad: Int, val satellite: String, val aos: String, val maxEl: Double,
                /** past passes only: receptions decoded during the window */
                val frames: Int? = null)
data class Health(
    val observer: String, val days: List<Day>, val passes: List<Pass>,
    val pastPasses: List<Pass>, val recentRate: Double?, val baselineRate: Double?,
)

object Api {
    private const val BASE = "https://overwatch.confinia.io/api/v1"

    /** exposed for extension calls that build their own query strings */
    suspend fun rawGet(path: String): String = get(path)

    private suspend fun get(path: String): String = withContext(Dispatchers.IO) {
        val conn = URL("$BASE/$path").openConnection() as HttpURLConnection
        conn.connectTimeout = 10_000; conn.readTimeout = 15_000
        try {
            if (conn.responseCode != 200) error("HTTP ${conn.responseCode}")
            conn.inputStream.bufferedReader().readText()
        } finally { conn.disconnect() }
    }

    suspend fun stations(): List<Station> =
        Json.parseToJsonElement(get("stations")).jsonArray.map { e ->
            val o = e.jsonObject
            Station(
                o["observer"]!!.jsonPrimitive.content,
                o["frames"]!!.jsonPrimitive.intOrNull ?: 0,
                o["satellites"]!!.jsonPrimitive.intOrNull ?: 0,
            )
        }

    suspend fun health(observer: String): Health {
        val o = Json.parseToJsonElement(
            get("stations/${URLEncoder.encode(observer, "UTF-8")}/health")).jsonObject
        return Health(
            observer = o["observer"]!!.jsonPrimitive.content,
            days = o["days"]!!.jsonArray.map { d ->
                val j = d.jsonObject
                Day(
                    j["day"]!!.jsonPrimitive.content,
                    j["frames"]!!.jsonPrimitive.intOrNull ?: 0,
                    j["passes"]!!.jsonPrimitive.intOrNull ?: 0,
                    j["hit_rate"]?.jsonPrimitive?.doubleOrNull,
                )
            },
            passes = o["next_passes"]!!.jsonArray.map { p ->
                val j = p.jsonObject
                Pass(
                    j["norad"]!!.jsonPrimitive.intOrNull ?: 0,
                    j["satellite"]!!.jsonPrimitive.content,
                    j["aos"]!!.jsonPrimitive.content,
                    j["max_el_deg"]!!.jsonPrimitive.doubleOrNull ?: 0.0,
                )
            },
            // tolerant of servers older than #366
            pastPasses = (o["past_passes"]?.jsonArray ?: emptyList()).map { p ->
                val j = p.jsonObject
                Pass(
                    j["norad"]!!.jsonPrimitive.intOrNull ?: 0,
                    j["satellite"]!!.jsonPrimitive.content,
                    j["aos"]!!.jsonPrimitive.content,
                    j["max_el_deg"]!!.jsonPrimitive.doubleOrNull ?: 0.0,
                    j["frames"]?.jsonPrimitive?.intOrNull,
                )
            },
            recentRate = o["recent_rate"]?.jsonPrimitive?.doubleOrNull,
            baselineRate = o["baseline_rate"]?.jsonPrimitive?.doubleOrNull,
        )
    }
}


data class Frame(val ts: String, val fields: Int)
data class PassDetail(val satellite: String, val aos: String, val los: String,
                      val maxEl: Double, val durationS: Int, val frames: List<Frame>)

suspend fun Api.passDetail(observer: String, norad: Int, aos: String): PassDetail {
    val path = "stations/${URLEncoder.encode(observer, "UTF-8")}/pass" +
        "?norad=$norad&aos=${URLEncoder.encode(aos, "UTF-8")}"
    val o = Json.parseToJsonElement(rawGet(path)).jsonObject
    return PassDetail(
        satellite = o["satellite"]!!.jsonPrimitive.content,
        aos = o["aos"]!!.jsonPrimitive.content,
        los = o["los"]!!.jsonPrimitive.content,
        maxEl = o["max_el_deg"]!!.jsonPrimitive.doubleOrNull ?: 0.0,
        durationS = o["duration_s"]!!.jsonPrimitive.intOrNull ?: 0,
        frames = o["frames"]!!.jsonArray.map { f ->
            val j = f.jsonObject
            Frame(j["ts"]!!.jsonPrimitive.content,
                  j["fields"]!!.jsonPrimitive.intOrNull ?: 0)
        })
}
