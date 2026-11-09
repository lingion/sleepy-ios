# School city boundary coverage

The comparison baseline is Android `v1.0.63`, commit
`a821c6ace1e3e5dbfd02c7fbd738bf2ca1c8a223`. Its
`SchoolCityIndex.kt`, `OfflineSchoolCityIndex.kt`,
`OfflineSchoolCityIndexTest.kt`, and `docs/catalog/city-boundary-coverage.md`
separate factual school locations from polygon coverage.

The iOS school-city JSON, compressed boundary asset, and source manifest are
byte-identical to that tag. Their SHA-256 values are respectively:

- `school_cities.json`: `4b49868feb33fad1fc9e6c4309cce798e5c21a42c4fd1e0db8cb57aa19ac1f27`
- `school_city_boundaries.bin.gz`: `708c35b31c82d030a1c498b13d854bc4c9f8204345d1d9d741217654b76a1769`
- `school_city_boundaries.source.json`: `800bd6f1b3d2d1dede03cebe9a24cc1ca1f0221288729c6ba7107df68214c2b1`

The existing production matcher already maps `昆山市` to the `苏州市`
recommendation boundary and `临夏州` to `临夏回族自治州`. The coverage
contract now uses that same matcher. It also requires the set of uncovered
metadata cities to equal the explicit, nonempty documented limitations, so a
new unknown location fails and a stale exclusion fails.

Only `新星市` is excluded in this snapshot. `新星职业技术学院` retains its
factual location and remains searchable. The asset has no separate Xinxing
polygon, and older neighboring polygons may cover parts of its area. Accurate
offline city geolocation there remains unsupported. No polygon, nearby-city
substitution, or metadata deletion was introduced.

Android's production protection against an older `台湾省` outline has also
been restored: that province name is excluded from city names and coordinate
results. The real asset supplies 22 Taiwan city/county boundaries. Coordinate
regressions mirror the tag for Taiwan cities/counties/islands, Hong Kong,
Macau, Kunshan, and a synthetic old province-only asset.

Official geography cross-checks read on 2026-11-09:

- Suzhou Statistics Bureau, 2025 statistical yearbook, administrative divisions:
  https://tjj.suzhou.gov.cn/sztjj/tjnj/2025/2025/zk/html/w01.pdf
  identifies Kunshan among Suzhou's four administered county-level cities.
- Linxia prefecture government's 2024-09-26 press-conference record:
  https://www.linxia.gov.cn/lxz/zwgk/fdzdgknr/xwfbh/art/2024/art_de7f026d356b49b0be924ddfdb09b01a.html
  uses `临夏州` for the government and identifies the region as
  `临夏回族自治州`.
- Xinjiang Production and Construction Corps exam authority, 2026-07-28
  college recruitment announcement:
  https://btpta.xjbt.gov.cn/c/2026-07-28/8495879.shtml
  confirms the college is located in the Thirteenth Division's Xinxing City.

The upstream source manifest still records unresolved DataV redistribution
authorization and the Taiwan mirror conversion limitation. This alignment
does not resolve those source limitations or claim new boundary coverage.
