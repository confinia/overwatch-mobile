# Overwatch — my station

Ground-station health in your pocket: open your station, see at a glance
whether it is hearing what it should, and when the next passes are.

Built entirely on the [Overwatch](https://overwatch.confinia.io) open-data
API — no account, nothing to sign into. Install it from your phone's browser
("Add to Home Screen"); it works the same on iPhone and Android.

- **Hit rate** — frames your station was heard decoding, divided by the passes
  that were geometrically available to it. Compared against **your own
  baseline**, never an absolute: Overwatch sees a station only through the
  satellites it tracks, so a low absolute number is not a verdict.
- **Next passes** — AOS and peak elevation for the tracked fleet.

One HTML file, one script, a service worker for the shell. The data is never
cached: the app exists to answer "is my station okay *right now*".

API: [`/v1/stations`](https://overwatch.confinia.io/api/v1/stations) ·
`/v1/stations/{callsign}/health` · docs at
[overwatch.confinia.io/api/v1](https://overwatch.confinia.io/api/v1).
