import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../../../domain/models/location_point.dart';
import '../../../core/strings/app_strings.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/utils/time_ago.dart';
import '../../../core/widgets/bevel_box.dart';
import '../../../core/widgets/pixel_heart_pin.dart';

/// One pin's worth of input: whose it is, what to call them, and which
/// accent they wear.
@immutable
class MapPerson {
  const MapPerson({
    required this.name,
    required this.point,
    required this.isMe,
  });

  final String name;
  final LocationPoint? point;
  final bool isMe;
}

/// The map itself: OSM tiles, a chunky pixel heart per person, and the
/// attribution OSM's tile-usage policy requires.
///
/// Kept separate from [LocationWindow] so the window's text half (distance
/// line, ghost controls) can be built and tested without a tile-fetching
/// map in the tree.
class CoupleMap extends StatefulWidget {
  const CoupleMap({super.key, required this.people, this.height = 220});

  final List<MapPerson> people;
  final double height;

  /// OSM's tile policy wants a real, identifying User-Agent — flutter_map
  /// turns this into `flutter_map (app.kehai)`. Bulk-downloading tiles is
  /// forbidden; two people's occasional dots is squarely within the
  /// acceptable-use terms.
  static const String userAgentPackageName = 'app.kehai';
  static const String osmTileUrl =
      'https://tile.openstreetmap.org/{z}/{x}/{y}.png';

  /// A comfortable "one person, no idea how far they roam" zoom.
  static const double singlePointZoom = 13;

  @override
  State<CoupleMap> createState() => _CoupleMapState();
}

class _CoupleMapState extends State<CoupleMap> {
  final MapController _controller = MapController();

  /// Once the user has panned or zoomed by hand, an arriving location no
  /// longer yanks the camera out from under them — the ⌖ button puts it
  /// back.
  bool _userMoved = false;
  bool _mapReady = false;

  List<LocationPoint> get _points =>
      widget.people.map((p) => p.point).nonNulls.toList();

  static LatLng _latLng(LocationPoint p) => LatLng(p.lat, p.lon);

  CameraFit? _fit() {
    final points = _points;
    if (points.length < 2) return null;
    return CameraFit.bounds(
      bounds: LatLngBounds.fromPoints(points.map(_latLng).toList()),
      // Room for the pins themselves and the attribution strip, so nobody
      // ends up sitting under the chrome.
      padding: const EdgeInsets.fromLTRB(48, 48, 48, 56),
    );
  }

  @override
  void didUpdateWidget(CoupleMap oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_userMoved) return;
    final before = oldWidget.people.map((p) => p.point).toList();
    final after = widget.people.map((p) => p.point).toList();
    if (_sameOrder(before, after)) return;
    _recenter(silent: true);
  }

  static bool _sameOrder(List<LocationPoint?> a, List<LocationPoint?> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  /// Re-fits the camera after the current frame — [MapController] only
  /// works once the map has built, and this can be called from
  /// [didUpdateWidget] mid-build.
  void _recenter({bool silent = false}) {
    if (!silent) setState(() => _userMoved = false);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_mapReady) return;
      final fit = _fit();
      final points = _points;
      if (fit != null) {
        _controller.fitCamera(fit);
      } else if (points.length == 1) {
        _controller.move(_latLng(points.first), CoupleMap.singlePointZoom);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final points = _points;

    return SizedBox(
      height: widget.height,
      child: BevelBox(
        style: BevelStyle.sunken,
        color: colors.bg,
        padding: const EdgeInsets.all(2),
        child: ClipRect(
          child: Stack(
            children: [
              FlutterMap(
                key: const Key('couple-map'),
                mapController: _controller,
                options: MapOptions(
                  initialCenter: points.isEmpty
                      ? const LatLng(0, 0)
                      : _latLng(points.first),
                  initialZoom: CoupleMap.singlePointZoom,
                  initialCameraFit: _fit(),
                  backgroundColor: colors.bg,
                  onMapReady: () => _mapReady = true,
                  onPositionChanged: (camera, hasGesture) {
                    if (hasGesture && !_userMoved) {
                      setState(() => _userMoved = true);
                    }
                  },
                ),
                children: [
                  TileLayer(
                    urlTemplate: CoupleMap.osmTileUrl,
                    userAgentPackageName: CoupleMap.userAgentPackageName,
                    maxNativeZoom: 19,
                    tileProvider: NetworkTileProvider(),
                  ),
                  MarkerLayer(
                    markers: [
                      for (final person in widget.people)
                        if (person.point != null)
                          _markerFor(context, person, person.point!),
                    ],
                  ),
                ],
              ),
              const Positioned(right: 4, bottom: 4, child: _Attribution()),
              if (_userMoved)
                Positioned(
                  left: 4,
                  bottom: 4,
                  child: _RecenterButton(onTap: _recenter),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Marker _markerFor(
    BuildContext context,
    MapPerson person,
    LocationPoint point,
  ) {
    final colors = context.colors;
    final relative = relativeTime(point.recorded);
    final label = AppStrings.locationAsOf(person.name, relative);
    return Marker(
      key: ValueKey('map-pin-${person.isMe ? 'me' : 'them'}'),
      point: _latLng(point),
      width: 160,
      height: 52,
      // The heart's bottom pixel is the pin tip, so the whole marker sits
      // above the coordinate.
      alignment: Alignment.topCenter,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          BevelBox(
            color: colors.surface,
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTextStyles.caption.copyWith(
                color: colors.ink,
                height: 1,
              ),
            ),
          ),
          const SizedBox(height: 2),
          PixelHeartPin(
            color: person.isMe ? colors.accent : colors.accent2,
            outline: colors.ink,
            semanticLabel: label,
          ),
        ],
      ),
    );
  }
}

/// OSM's tile policy requires visible attribution. Pixel-styled to match
/// the chrome, but plain readable text at caption size — a credit nobody
/// can read isn't a credit.
class _Attribution extends StatelessWidget {
  const _Attribution();

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return BevelBox(
      color: colors.surface,
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      child: Text(
        AppStrings.mapAttribution,
        style: AppTextStyles.caption.copyWith(color: colors.ink, height: 1),
      ),
    );
  }
}

class _RecenterButton extends StatelessWidget {
  const _RecenterButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Tooltip(
      message: AppStrings.locationRecenter,
      child: Semantics(
        button: true,
        label: AppStrings.locationRecenter,
        child: GestureDetector(
          key: const Key('map-recenter'),
          onTap: onTap,
          child: MouseRegion(
            cursor: SystemMouseCursors.click,
            child: BevelBox(
              color: colors.chrome,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: Text(
                '⌖',
                style: AppTextStyles.caption.copyWith(
                  color: colors.ink,
                  height: 1,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
