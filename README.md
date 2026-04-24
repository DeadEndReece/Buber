# BUBER

BUBER adds a Career Mode taxi and ride-share service to BeamNG.drive. Go on duty, accept fares, pick up passengers, complete trips, earn Career money, and build your driver rating to unlock bigger jobs.

## Features

- Career Mode taxi jobs with pickup and drop-off routing.
- BUBER UI app with a dashboard, progression view, fare popup, and live taxi meter.
- Direct point-to-point fares for normal vehicles.
- Shared rides with multiple drop-offs after progression unlocks.
- Bus route jobs for high-capacity vehicles on maps with bus route data.
- Passenger types with different expectations, tips, and rating behavior.
- Driver rating progression from 0.0 to 5.0.
- Rating-based seat limits, payout limits, and route unlocks.
- Vehicle class pay multipliers based on vehicle performance.
- Fare streak bonuses for completing jobs back to back.
- Pickup, drop-off, boarding, and route guidance in the UI.
- Return-to-vehicle grace timer after passengers are onboard.
- Customizable UI size, opacity, popup position, meter position, and meter visibility.
- Saved UI settings and saved driver rating per Career save.

## Installation

Install `Buber.zip` like a normal BeamNG.drive mod:

1. Put the zip in your BeamNG.drive `mods` folder.
2. Enable the mod in BeamNG.drive.
3. Start or load a Career Mode save.
4. Add the `BUBER` UI app to your layout.

## How To Play

1. Enter a valid personal vehicle in Career Mode.
2. Open the BUBER UI app, or press `T` to toggle the overlay.
3. Press the duty button to go `On Duty`.
4. Wait for dispatch to offer a fare.
5. Accept or reject the fare from the popup or dashboard.
6. Follow the route to the pickup point.
7. Stop in the marked zone and wait for passenger service to finish.
8. Drive to the destination or next stop and complete the fare.

For shared rides and bus routes, follow each stop in order. Bus route jobs may ask you to stop, open the doors, wait for boarding or drop-off, then close the doors before continuing.

## Passenger Types

BUBER includes several passenger groups. Each one rewards a different driving style:

| Passenger type | What they care about |
| --- | --- |
| Standard | Balanced speed, comfort, and efficiency. |
| Commuter | Punctual, steady driving. |
| Business | Fast, efficient trips with fewer delays. |
| Executive | Smooth, premium service. |
| Family | Safe, calm driving with enough seats. |
| Luxury | Comfort and smoothness over outright speed. |
| Party Group | Larger groups that still expect safe driving. |
| Student | Budget fares with simple efficiency bonuses. |
| Thrill Seeker | Speed and excitement without getting too reckless. |
| Tourist | Slower, smoother, scenic-style driving. |

## Driver Rating And Progression

Your driver rating is saved in your Career save and controls what BUBER will offer you. Completing fares improves your rating based on passenger satisfaction. Abandoning a fare after passengers are onboard lowers it.

Progression unlocks higher seat limits, better earning potential, shared rides, and bus routes.

| Driver rating | What unlocks |
| ---: | --- |
| 0.0 | Direct fares and up to 4 usable passenger seats. |
| 1.0 | Better direct fares and up to 8 usable passenger seats. |
| 2.0 | Shared rides, bus routes, and up to 18 usable passenger seats. |
| 3.0 | Larger route work and up to 35 usable passenger seats. |
| 4.0 | High-capacity fares and up to 65 usable passenger seats. |
| 5.0 | Full vehicle passenger capacity. |

The in-game Progression tab shows your exact current limits and next unlock.

## Payouts

Fare pay is based on distance, passenger count, passenger type, tips, fare streak, vehicle class, and your driver rating. Bigger or faster vehicles can earn more, but BUBER keeps rewards balanced through progression so early jobs stay reasonable.

Hardcore Mode and Career economy settings can also affect rewards.

## Vehicle And Route Notes

- BUBER is made for BeamNG.drive Career Mode.
- You need to be in a valid personal vehicle to take fares.
- Loaned vehicles, walking mode, or Career challenges that disable taxi income can make BUBER unavailable.
- Your vehicle's real seat count matters, but your driver rating controls how many seats BUBER will use.
- Bus route jobs need a high-capacity vehicle and a level with usable bus stops and route data.
- If you leave the vehicle before pickup, the fare is cancelled.
- If you leave after passengers are onboard, you get a short timer to return before the fare is abandoned.

## UI Tips

- Use the yellow `B` tab to open or close the BUBER panel.
- Press `T` to toggle the BUBER overlay.
- Open the gear menu to adjust panel size, opacity, popup location, meter location, and meter visibility.
- Move the UI app in BeamNG.drive's UI editor to dock it near a different screen edge.

## Configuration

All tunable gameplay values are kept in a single file:

```
lua/ge/extensions/gameplay/taxiConfig.lua
```

No game logic lives in this file — it is purely data. Edit it to adjust timing, payouts, progression, zone sizes, and more without touching the core extension. After editing, reload the mod or restart Career Mode for changes to take effect.

### How to edit

1. Open `taxiConfig.lua` in any text editor.
2. Find the section you want to change (each section is clearly labelled with a comment header).
3. Change the value to the right of the `=`. Numbers, strings, and `true`/`false` are all valid depending on the field.
4. Save the file, then reload the mod in BeamNG.drive.

> **Do not rename or remove any keys.** The extension reads each field by name. Removing a key will cause that feature to fall back to a hardcoded default or error silently.

---

### Brand (`M.brand`)

Controls the display name and where the driver rating is saved inside your Career save slot.

| Key | Default | Purpose |
| --- | --- | --- |
| `name` | `"BUBER"` | Display name shown in UI toasts and messages. |
| `ratingSaveDir` | `"buber"` | Subfolder inside your Career save's `career/` directory. |
| `ratingSaveFile` | `"taxiRating.json"` | Filename for the persisted driver rating data. |

---

### Timing (`M.timing`)

All values are in seconds.

| Key | Default | Purpose |
| --- | --- | --- |
| `jobOfferIntervalMin` | `5` | Minimum wait between consecutive fare offers. |
| `jobOfferIntervalMax` | `45` | Maximum wait between fare offers. |
| `jobOfferPrepareLeadTime` | `3` | How many seconds before an offer the fare is pre-generated. |
| `jobAcceptTimeout` | `30` | Time to accept or reject a fare before it auto-rejects. |
| `completedFareDisplay` | `6` | How long the fare-complete summary stays on screen. |
| `updateInterval` | `1` | Main loop tick rate. |
| `routeRestoreCooldown` | `2.0` | Minimum gap between route-restore attempts. |
| `returnToVehicleGrace` | `20` | Grace period to return to your vehicle after leaving it mid-dropoff. |

---

### Taxi Zones (`M.zones`)

All values are in metres.

| Key | Default | Purpose |
| --- | --- | --- |
| `stopRadius` | `5` | Arrival detection radius at pickup and dropoff points. |
| `stopHeight` | `2.5` | Visual cylinder height for zone markers. |
| `drawRadius` | `1` | Visual cylinder radius for zone markers. |
| `pickupSearchRadius` | `500` | How far from the player to search for pickup spots. |
| `minPickupDistance` | `60` | Minimum distance for a valid pickup from the player's position. |
| `pickupCacheRefreshDist` | `125` | Rebuild the pickup cache after driving this far. |
| `maxPickupSamples` | `8` | Maximum pickup candidates evaluated per fare offer. |
| `maxDropoffSamples` | `24` | Maximum dropoff candidates evaluated per fare offer. |

---

### Passenger Service (`M.service`)

| Key | Default | Purpose |
| --- | --- | --- |
| `stopServiceSeconds` | `3` | Time passengers need to board or exit at non-bus stops. |
| `stopSpeedThreshold` | `0.75` | Maximum speed in m/s to count as fully stopped. |
| `busPassengerServiceRate` | `2` | Passengers processed per second at bus stops. |

---

### Multi-Stop / Bus Routes (`M.multiStop`)

| Key | Default | Purpose |
| --- | --- | --- |
| `vehicleSeatThreshold` | `18` | Minimum seat count to qualify for bus-route fares. |
| `emptyStopChance` | `0.35` | Probability (0–1) that a generated bus stop has no drop-offs. |
| `requiredRating` | `2.0` | Driver rating needed to unlock multi-stop and bus routes. |

---

### Shared Rides (`M.sharedRide`)

| Key | Default | Purpose |
| --- | --- | --- |
| `minSeats` | `4` | Minimum available seats before a shared ride can be offered. |
| `offerChance` | `0.25` | Probability (0–1) of a shared ride versus a direct fare. |
| `minDropoffDistance` | `250` | Minimum distance between consecutive shared-ride drop-offs. |
| `maxDropoffs` | `3` | Maximum number of drop-off points in a single shared ride. |

---

### Fare Calculation (`M.fare`)

| Key | Default | Purpose |
| --- | --- | --- |
| `distanceMultiplier` | `3` | Base scaling factor applied to distance when calculating a fare. |
| `suggestedSpeed` | `18` | Reference speed in m/s used to compute the speed bonus/penalty. |
| `minDropoffDistance` | `600` | Minimum pickup-to-dropoff distance for direct fares (metres). |

---

### Driver Rating (`M.rating`)

| Key | Default | Purpose |
| --- | --- | --- |
| `sumPerLevel` | `25` | Rating points required per whole star level. |
| `maxRating` | `5` | Hard ceiling for driver rating. |
| `abandonBasePenalty` | `0.10` | Rating penalty for the first abandonment in a shift. |
| `abandonScalePenalty` | `0.15` | Additional penalty for each subsequent abandonment. |
| `abandonMaxPenalty` | `1.0` | Hard cap on a single abandonment penalty. |

**`seatCapCurve`** — A list of `{rating, value}` pairs that map driver rating to the maximum number of passenger seats BUBER will use. Intermediate ratings are interpolated. Use `math.huge` for unlimited seats.

**`milestones`** — A list of `{rating, label, description}` entries shown in the in-game Progression tab. Add, remove, or rename entries freely; they have no effect on game logic.

---

### Vehicle Class Pay Tiers (`M.vehicle.classTiers`)

Each class entry maps a Performance Index (PI) range to a pay multiplier range. BUBER picks the class based on the current vehicle's PI and interpolates the multiplier within the range.

| Class | PI Range | Multiplier Range |
| --- | --- | --- |
| D — Economy/Utility | 0–20 | 0.70–0.90× |
| C — Standard | 21–40 | 0.95–1.10× |
| B — Sports | 41–65 | 1.15–1.30× |
| A — High Performance | 66–85 | 1.35–1.55× |
| S — Super Sports | 86–100 | 1.65–1.90× |
| X — Modified | 101–120 | 2.00–2.20× |

**`seatPackRules`** and **`capsuleSeatPacks`** — Pattern-matched lists that tell BUBER how many seats specific vehicle part names provide. Add entries here if a modded vehicle is not being detected correctly.

---

### Payout Limits (`M.payout`)

Two profiles exist: `direct` (point-to-point fares) and `multistop` (bus and shared rides). Both share the same shape.

| Key | Purpose |
| --- | --- |
| `softCap` | Earnings above this are scaled down by `softCapOverflowRate`. |
| `softCapOverflowRate` | Fraction of earnings above the soft cap that is kept (e.g. `0.30` = 30 cents per dollar over cap). |
| `multiplierStackCap` | Maximum combined multiplier from all bonuses. |
| `tipSoftCaps` | Per-driver-level (0–5) soft cap on tip amounts. |
| `tipBasePercentCaps` | Per-driver-level maximum tip as a fraction of the base fare. |
| `tipSoftCapOverflowRate` | Fraction of tip earnings above the soft cap that is kept. |
| `ratingHardCapCurve` | Rating-keyed curve that sets the absolute maximum payout at each rating level. |

The `multistop` profile additionally has:

| Key | Purpose |
| --- | --- |
| `fullPassengerCount` | Passengers above this number earn at a reduced rate. |
| `extraPassengerRate` | Earnings rate for passengers above `fullPassengerCount`. |
| `fullDistanceMeters` | Distance above which earnings are reduced. |
| `extraDistanceRate` | Earnings rate for distance above `fullDistanceMeters`. |

---

### Visual Zone Colors (`M.visual`)

Colors are `{r, g, b, a}` tables with values from `0` to `1`.

- `zoneColors.pickup.active` / `inactive` — Color of the pickup zone marker.
- `zoneColors.dropoff.active` / `inactive` — Color of the dropoff zone marker.
- `debugSpotColors` — Colors for the debug overlay (`all`, `pickup`, `bus`, `reserved`).

---

### Passenger Modules (`M.passengerModules`)

| Key | Default | Purpose |
| --- | --- | --- |
| `path` | `"/lua/ge/extensions/gameplay/taxiPassengers/"` | Directory BUBER scans for passenger type modules. Each `.lua` file in this folder is loaded as a separate passenger type. |

To add a new passenger type, drop a new `.lua` file into the `taxiPassengers/` folder following the same structure as the existing ones. To disable a type, remove or rename its file.

---

## License

BUBER is licensed under the GPL-3.0 license. See [LICENSE](LICENSE) for details.
