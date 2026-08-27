package io.confinia.overwatch

import android.content.Context
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import java.time.ZonedDateTime
import java.time.format.DateTimeFormatter

/**
 * One screen, iso with iPhone and the PWA: pick your station once, then the
 * app opens straight onto it. Nothing between launch and "is my station okay?"
 */
class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // Surface, et pas seulement MaterialTheme : sans elle, LocalContentColor
        // reste noir et chaque Text sans couleur explicite s'affichait noir sur
        // le fond sombre — titres de stations illisibles, constaté en
        // comparant à l'iPhone. Surface pose le fond du thème ET la couleur de
        // contenu qui va avec.
        setContent {
            MaterialTheme(colorScheme = darkColorScheme()) {
                Surface(Modifier.fillMaxSize(),
                        color = MaterialTheme.colorScheme.background) { Screen() }
            }
        }
    }
}

private fun prefs(c: Context) = c.getSharedPreferences("overwatch", Context.MODE_PRIVATE)

@Composable
private fun Screen() {
    val context = LocalContext.current
    var mine by remember { mutableStateOf(prefs(context).getString("station", "") ?: "") }
    var open by remember { mutableStateOf(mine.ifEmpty { null }) }
    var pass by remember { mutableStateOf<Pass?>(null) }
    when {
        open == null -> StationList(onPick = { open = it })
        pass != null -> PassDetailScreen(observer = open!!, pass = pass!!,
                                         onBack = { pass = null })
        else -> StationScreen(
            observer = open!!, mine = mine,
            onBack = { open = null },
            onMine = { v ->
                mine = v
                prefs(context).edit().putString("station", v).apply()
            },
            onPass = { pass = it })
    }
}

@Composable
private fun StationList(onPick: (String) -> Unit) {
    var stations by remember { mutableStateOf<List<Station>>(emptyList()) }
    var query by remember { mutableStateOf("") }
    var failed by remember { mutableStateOf(false) }
    LaunchedEffect(Unit) {
        try { stations = Api.stations() } catch (e: Exception) { failed = true }
    }
    Column(Modifier.fillMaxSize().statusBarsPadding().padding(16.dp)) {
        Text("My station", fontSize = 22.sp, fontWeight = FontWeight.Bold)
        Spacer(Modifier.height(10.dp))
        OutlinedTextField(query, { query = it }, Modifier.fillMaxWidth(),
            placeholder = { Text("Your callsign or station") }, singleLine = true)
        Spacer(Modifier.height(8.dp))
        if (failed) Text("Couldn't reach Overwatch", color = Color(0xFFF0A35E))
        LazyColumn {
            items(stations.filter {
                query.isBlank() || it.observer.contains(query, ignoreCase = true)
            }.take(30)) { s ->
                Column(Modifier.fillMaxWidth().clickable { onPick(s.observer) }
                    .padding(vertical = 10.dp)) {
                    Text(s.observer, fontWeight = FontWeight.SemiBold)
                    Text("${s.frames} frames · ${s.satellites} satellites · 7 days",
                        fontSize = 12.sp, color = MaterialTheme.colorScheme.onSurfaceVariant)
                }
                HorizontalDivider()
            }
        }
    }
}

@Composable
private fun StationScreen(observer: String, mine: String,
                          onBack: () -> Unit, onMine: (String) -> Unit,
                          onPass: (Pass) -> Unit = {}) {
    var health by remember { mutableStateOf<Health?>(null) }
    var failed by remember { mutableStateOf(false) }
    LaunchedEffect(observer) {
        try { health = Api.health(observer) } catch (e: Exception) { failed = true }
    }
    Column(Modifier.fillMaxSize().statusBarsPadding().padding(16.dp)) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            TextButton(onClick = onBack) { Text("‹ stations") }
            Spacer(Modifier.weight(1f))
            TextButton(onClick = { onMine(if (mine == observer) "" else observer) }) {
                Text(if (mine == observer) "My station ✓" else "Set as mine", fontSize = 12.sp)
            }
        }
        Text(observer, fontSize = 18.sp, fontWeight = FontWeight.Bold)
        Spacer(Modifier.height(10.dp))
        val h = health
        when {
            failed -> Text("Couldn't load $observer", color = Color(0xFFF0A35E))
            h == null -> CircularProgressIndicator()
            else -> {
                // The verdict is RELATIVE — same thresholds as the server-side
                // detector. Colour only when there is a baseline to fall from.
                val r = h.recentRate
                val b = h.baselineRate
                val (verdict, colour) = when {
                    r == null -> "no recent data" to Color(0xFFF0A35E)
                    b != null && b >= 0.05 && r <= b * 0.25 ->
                        "far below your own baseline" to Color(0xFFFF6B6B)
                    b != null && b >= 0.05 && r <= b * 0.6 ->
                        "below your own baseline" to Color(0xFFF0A35E)
                    else -> "hearing as usual" to Color(0xFF39D98A)
                }
                Card {
                    Column(Modifier.padding(14.dp)) {
                        Text(r?.let { "${(it * 100).toInt()}%" } ?: "—",
                            fontSize = 40.sp, fontWeight = FontWeight.Bold, color = colour)
                        Text(verdict, color = MaterialTheme.colorScheme.onSurfaceVariant)
                        b?.let { Text("your baseline ${(it * 100).toInt()}%",
                            fontSize = 12.sp, color = MaterialTheme.colorScheme.onSurfaceVariant) }
                        Spacer(Modifier.height(8.dp))
                        // 21-day sparkline; grey = no passes that day (unknown, not zero)
                        Row(Modifier.height(56.dp), verticalAlignment = Alignment.Bottom,
                            horizontalArrangement = Arrangement.spacedBy(2.dp)) {
                            h.days.takeLast(21).forEach { d ->
                                Box(Modifier.weight(1f)
                                    // clamped: rates above 1.0 are real
                                    // (several frames per pass) and must not
                                    // overflow the row
                                    .height(if (d.hitRate == null) 3.dp
                                            else (4 + minOf(d.hitRate, 1.0) * 52).dp)
                                    .clip(RoundedCornerShape(topStart = 2.dp, topEnd = 2.dp))
                                    .background(if (d.hitRate == null)
                                        MaterialTheme.colorScheme.outlineVariant
                                        else Color(0xFF5AA9FF)))
                            }
                        }
                        Text("hit rate — frames heard / passes available",
                            fontSize = 11.sp, color = MaterialTheme.colorScheme.onSurfaceVariant)
                    }
                }
                if (h.passes.isNotEmpty()) PassCard("Next passes", h.passes)
                if (h.pastPasses.isNotEmpty())
                    PassCard("Recent passes", h.pastPasses, onTap = onPass)
            }
        }
        Spacer(Modifier.weight(1f))
        Text("Overwatch sees your station only through the satellites it tracks — " +
             "compare against your own history, not an absolute.",
            fontSize = 11.sp, color = MaterialTheme.colorScheme.onSurfaceVariant)
    }
}

private fun fmt(iso: String): String = try {
    ZonedDateTime.parse(iso.replace("+00:00", "Z"))
        .format(DateTimeFormatter.ofPattern("EEE HH:mm"))
} catch (e: Exception) { iso }


/** One card of passes. Past passes carry frames: green when the station heard
 *  the pass, red "nothing heard" when it did not — the per-pass "was it me?". */
@Composable
private fun PassCard(title: String, passes: List<Pass>,
                     onTap: ((Pass) -> Unit)? = null) {
    val context = LocalContext.current
    Spacer(Modifier.height(10.dp))
    Card {
        Column(Modifier.padding(14.dp)) {
            Text(title, fontWeight = FontWeight.SemiBold)
            passes.forEach { p ->
                Row(Modifier.fillMaxWidth()
                        .let { m -> if (onTap != null)
                            m.clickable { onTap(p) } else m }
                        .padding(vertical = 4.dp),
                    verticalAlignment = Alignment.CenterVertically) {
                    // "about" = our own control room page for that satellite
                    Text(p.satellite, color = Color(0xFF5AA9FF),
                        modifier = Modifier.clickable {
                            context.startActivity(android.content.Intent(
                                android.content.Intent.ACTION_VIEW,
                                android.net.Uri.parse(
                                    "https://overwatch.confinia.io/#${p.norad}")))
                        })
                    Spacer(Modifier.weight(1f))
                    p.frames?.let { f ->
                        Text(if (f > 0) "$f frames" else "nothing heard",
                            fontSize = 12.sp,
                            color = if (f > 0) Color(0xFF39D98A) else Color(0xFFFF6B6B))
                        Spacer(Modifier.width(8.dp))
                    }
                    Text("${fmt(p.aos)} · ${p.maxEl.toInt()}°",
                        color = MaterialTheme.colorScheme.onSurfaceVariant)
                }
            }
        }
    }
}


/** Frame-by-frame view of one pass (#368). Ticks only around the middle of
 *  the bar suggest a horizon problem; across the whole bar, a healthy chain. */
@Composable
private fun PassDetailScreen(observer: String, pass: Pass, onBack: () -> Unit) {
    var detail by remember { mutableStateOf<PassDetail?>(null) }
    var failed by remember { mutableStateOf(false) }
    LaunchedEffect(pass) {
        try { detail = Api.passDetail(observer, pass.norad, pass.aos) }
        catch (e: Exception) { failed = true }
    }
    Column(Modifier.fillMaxSize().statusBarsPadding().padding(16.dp)) {
        TextButton(onClick = onBack) { Text("‹ ${observer.take(24)}") }
        Text(pass.satellite, fontSize = 18.sp, fontWeight = FontWeight.Bold)
        Spacer(Modifier.height(10.dp))
        val d = detail
        when {
            failed -> Text("Couldn't load this pass", color = Color(0xFFF0A35E))
            d == null -> CircularProgressIndicator()
            else -> {
                Card {
                    Column(Modifier.padding(14.dp)) {
                        Text("${fmt(d.aos)} · max ${d.maxEl.toInt()}° · ${d.durationS / 60} min",
                            color = MaterialTheme.colorScheme.onSurfaceVariant)
                        Spacer(Modifier.height(10.dp))
                        // the timeline: one tick per frame at its offset
                        androidx.compose.foundation.layout.BoxWithConstraints(
                            Modifier.fillMaxWidth().height(20.dp)) {
                            val w = maxWidth
                            Box(Modifier.fillMaxWidth().height(6.dp)
                                .align(Alignment.CenterStart)
                                .clip(RoundedCornerShape(3.dp))
                                .background(MaterialTheme.colorScheme.outlineVariant))
                            d.frames.forEach { f ->
                                val x = offsetIn(d, f)
                                Box(Modifier.padding(start = w * x)
                                    .width(2.dp).height(16.dp)
                                    .align(Alignment.CenterStart)
                                    .background(if (f.fields > 0) Color(0xFF39D98A)
                                                else Color(0xFF5AA9FF)))
                            }
                        }
                        Text(if (d.frames.isEmpty()) "No frames decoded during this pass."
                             else "${d.frames.size} frames — position along the bar is position in the pass",
                            fontSize = 11.sp,
                            color = MaterialTheme.colorScheme.onSurfaceVariant)
                    }
                }
                if (d.frames.isNotEmpty()) {
                    Spacer(Modifier.height(10.dp))
                    Card {
                        Column(Modifier.padding(14.dp)) {
                            Text("Frames", fontWeight = FontWeight.SemiBold)
                            LazyColumn {
                                items(d.frames) { f ->
                                    Row(Modifier.fillMaxWidth().padding(vertical = 3.dp)) {
                                        Text(hms(f.ts))
                                        Spacer(Modifier.weight(1f))
                                        Text(if (f.fields > 0) "${f.fields} fields decoded"
                                             else "received, not decoded",
                                            fontSize = 12.sp,
                                            color = if (f.fields > 0) Color(0xFF39D98A)
                                                    else MaterialTheme.colorScheme.onSurfaceVariant)
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}

private fun offsetIn(d: PassDetail, f: Frame): Float = try {
    val a = ZonedDateTime.parse(d.aos.replace("+00:00", "Z"))
    val t = ZonedDateTime.parse(f.ts.replace("+00:00", "Z"))
    val x = java.time.Duration.between(a, t).seconds.toFloat() / d.durationS
    x.coerceIn(0f, 1f)
} catch (e: Exception) { 0f }

private fun hms(iso: String): String = try {
    ZonedDateTime.parse(iso.replace("+00:00", "Z"))
        .format(DateTimeFormatter.ofPattern("HH:mm:ss"))
} catch (e: Exception) { iso }
