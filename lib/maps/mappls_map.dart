import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart' as g;
import 'package:mappls_gl/mappls_gl.dart' as m;
import 'package:vite_captain/maps/google_map_view.dart';
import 'package:vite_captain/services/app_config.dart';

typedef LatLng = m.LatLng;
typedef LatLngBounds = m.LatLngBounds;
typedef CameraPosition = m.CameraPosition;

@immutable
class MarkerId {
  const MarkerId(this.value);
  final String value;

  @override
  bool operator ==(Object other) => other is MarkerId && other.value == value;

  @override
  int get hashCode => value.hashCode;
}

@immutable
class PolylineId {
  const PolylineId(this.value);
  final String value;

  @override
  bool operator ==(Object other) => other is PolylineId && other.value == value;

  @override
  int get hashCode => value.hashCode;
}

@immutable
class InfoWindow {
  const InfoWindow({this.title, this.snippet});
  final String? title;
  final String? snippet;

  static const InfoWindow noText = InfoWindow();

  String? get label {
    final parts = <String>[
      if ((title ?? '').trim().isNotEmpty) title!.trim(),
      if ((snippet ?? '').trim().isNotEmpty) snippet!.trim(),
    ];
    return parts.isEmpty ? null : parts.join('\n');
  }

  @override
  bool operator ==(Object other) =>
      other is InfoWindow && other.title == title && other.snippet == snippet;

  @override
  int get hashCode => Object.hash(title, snippet);
}

/// Marker icon. Hue icons are drawn as pins at runtime; byte icons are used as-is.
@immutable
class BitmapDescriptor {
  const BitmapDescriptor._hue(this.hue) : bytes = null, _id = null;
  BitmapDescriptor._bytes(Uint8List this.bytes)
      : hue = null,
        _id = 'vv-bytes-${_nextId++}';

  final double? hue;
  final Uint8List? bytes;
  final String? _id;

  static int _nextId = 0;

  static const double hueRed = 0.0;
  static const double hueOrange = 30.0;
  static const double hueYellow = 60.0;
  static const double hueGreen = 120.0;
  static const double hueCyan = 180.0;
  static const double hueAzure = 210.0;
  static const double hueBlue = 240.0;
  static const double hueViolet = 270.0;
  static const double hueMagenta = 300.0;
  static const double hueRose = 330.0;

  static const BitmapDescriptor defaultMarker = BitmapDescriptor._hue(hueRed);

  static BitmapDescriptor defaultMarkerWithHue(double hue) => BitmapDescriptor._hue(hue % 360);

  static BitmapDescriptor fromBytes(Uint8List bytes) => BitmapDescriptor._bytes(bytes);

  String get imageName => _id ?? 'vv-hue-${hue!.round()}';

  @override
  bool operator ==(Object other) => other is BitmapDescriptor && other.imageName == imageName;

  @override
  int get hashCode => imageName.hashCode;
}

@immutable
class Marker {
  const Marker({
    required this.markerId,
    this.position = const LatLng(0, 0),
    this.icon = BitmapDescriptor.defaultMarker,
    this.infoWindow = InfoWindow.noText,
    this.anchor = const Offset(0.5, 1.0),
    this.rotation = 0.0,
    this.alpha = 1.0,
    this.flat = false,
    this.visible = true,
    this.zIndex = 0.0,
    this.draggable = false,
    this.consumeTapEvents = false,
    this.onTap,
  });

  final MarkerId markerId;
  final LatLng position;
  final BitmapDescriptor icon;
  final InfoWindow infoWindow;
  final Offset anchor;
  final double rotation;
  final double alpha;
  final bool flat;
  final bool visible;
  final double zIndex;
  final bool draggable;
  final bool consumeTapEvents;
  final VoidCallback? onTap;

  Marker copyWith({
    LatLng? positionParam,
    BitmapDescriptor? iconParam,
    InfoWindow? infoWindowParam,
    Offset? anchorParam,
    double? rotationParam,
    double? alphaParam,
    bool? visibleParam,
    double? zIndexParam,
    VoidCallback? onTapParam,
  }) {
    return Marker(
      markerId: markerId,
      position: positionParam ?? position,
      icon: iconParam ?? icon,
      infoWindow: infoWindowParam ?? infoWindow,
      anchor: anchorParam ?? anchor,
      rotation: rotationParam ?? rotation,
      alpha: alphaParam ?? alpha,
      flat: flat,
      visible: visibleParam ?? visible,
      zIndex: zIndexParam ?? zIndex,
      draggable: draggable,
      consumeTapEvents: consumeTapEvents,
      onTap: onTapParam ?? onTap,
    );
  }

  bool _sameLook(Marker other) =>
      other.position == position &&
      other.icon == icon &&
      other.infoWindow == infoWindow &&
      other.anchor == anchor &&
      other.rotation == rotation &&
      other.alpha == alpha &&
      other.zIndex == zIndex;

  @override
  bool operator ==(Object other) => other is Marker && other.markerId == markerId;

  @override
  int get hashCode => markerId.hashCode;
}

@immutable
class Polyline {
  const Polyline({
    required this.polylineId,
    this.points = const <LatLng>[],
    this.color = Colors.black,
    this.width = 10,
    this.visible = true,
    this.geodesic = false,
    this.zIndex = 0,
    this.consumeTapEvents = false,
    this.onTap,
  });

  final PolylineId polylineId;
  final List<LatLng> points;
  final Color color;
  final int width;
  final bool visible;
  final bool geodesic;
  final int zIndex;
  final bool consumeTapEvents;
  final VoidCallback? onTap;

  bool _sameLook(Polyline other) =>
      other.color == color && other.width == width && listEquals(other.points, points);

  @override
  bool operator ==(Object other) => other is Polyline && other.polylineId == polylineId;

  @override
  int get hashCode => polylineId.hashCode;
}

/// Camera update that can be applied to Google Maps or Mapple (Mappls).
class CameraUpdate {
  const CameraUpdate._(this._mappls, this._google);
  final m.CameraUpdate Function() _mappls;
  final g.CameraUpdate Function() _google;

  m.CameraUpdate toMappls() => _mappls();
  g.CameraUpdate toGoogle() => _google();

  static g.LatLng _g(LatLng p) => g.LatLng(p.latitude, p.longitude);

  static CameraUpdate newLatLng(LatLng latLng) => CameraUpdate._(
        () => m.CameraUpdate.newLatLng(latLng),
        () => g.CameraUpdate.newLatLng(_g(latLng)),
      );

  static CameraUpdate newLatLngZoom(LatLng latLng, double zoom) => CameraUpdate._(
        () => m.CameraUpdate.newLatLngZoom(latLng, zoom),
        () => g.CameraUpdate.newLatLngZoom(_g(latLng), zoom),
      );

  static CameraUpdate newCameraPosition(CameraPosition position) => CameraUpdate._(
        () => m.CameraUpdate.newCameraPosition(position),
        () => g.CameraUpdate.newCameraPosition(
          g.CameraPosition(
            target: _g(position.target),
            zoom: position.zoom,
            bearing: position.bearing,
            tilt: position.tilt,
          ),
        ),
      );

  static CameraUpdate newLatLngBounds(LatLngBounds bounds, double padding) {
    final safe = _safeBounds(bounds);
    return CameraUpdate._(
      () => m.CameraUpdate.newLatLngBounds(
        safe,
        left: padding,
        top: padding,
        right: padding,
        bottom: padding,
      ),
      () => g.CameraUpdate.newLatLngBounds(
        g.LatLngBounds(southwest: _g(safe.southwest), northeast: _g(safe.northeast)),
        padding,
      ),
    );
  }

  static CameraUpdate zoomIn() => CameraUpdate._(m.CameraUpdate.zoomIn, g.CameraUpdate.zoomIn);
  static CameraUpdate zoomOut() => CameraUpdate._(m.CameraUpdate.zoomOut, g.CameraUpdate.zoomOut);
  static CameraUpdate zoomTo(double zoom) =>
      CameraUpdate._(() => m.CameraUpdate.zoomTo(zoom), () => g.CameraUpdate.zoomTo(zoom));
  static CameraUpdate zoomBy(double amount) =>
      CameraUpdate._(() => m.CameraUpdate.zoomBy(amount), () => g.CameraUpdate.zoomBy(amount));
  static CameraUpdate scrollBy(double dx, double dy) =>
      CameraUpdate._(() => m.CameraUpdate.scrollBy(dx, dy), () => g.CameraUpdate.scrollBy(dx, dy));

  static LatLngBounds _safeBounds(LatLngBounds b) {
    const minSpan = 0.0005;
    final sw = b.southwest;
    final ne = b.northeast;
    if ((ne.latitude - sw.latitude).abs() >= minSpan || (ne.longitude - sw.longitude).abs() >= minSpan) {
      return b;
    }
    return LatLngBounds(
      southwest: LatLng(sw.latitude - minSpan, sw.longitude - minSpan),
      northeast: LatLng(ne.latitude + minSpan, ne.longitude + minSpan),
    );
  }
}

abstract class MapplsViewController {
  Future<void> animateCamera(CameraUpdate update, {Duration? duration});
  Future<void> moveCamera(CameraUpdate update);
  Future<LatLngBounds> getVisibleRegion();
  Future<double> getZoomLevel();
  Future<void> showMarkerInfoWindow(MarkerId id);
  Future<void> hideMarkerInfoWindow(MarkerId id);
  Future<bool> isMarkerInfoWindowShown(MarkerId id);
  void dispose() {}
}

class _MapplsNativeController extends MapplsViewController {
  _MapplsNativeController(this._map, this._state);

  final m.MapplsMapController _map;
  final _MapplsViewState _state;

  @override
  Future<void> animateCamera(CameraUpdate update, {Duration? duration}) async {
    await _map.animateCamera(update.toMappls(), duration: duration);
  }

  @override
  Future<void> moveCamera(CameraUpdate update) async {
    await _map.moveCamera(update.toMappls());
  }

  @override
  Future<LatLngBounds> getVisibleRegion() => _map.getVisibleRegion();

  @override
  Future<double> getZoomLevel() async => _map.cameraPosition?.zoom ?? 0;

  @override
  Future<void> showMarkerInfoWindow(MarkerId id) => _state._setInfoWindow(id, true);

  @override
  Future<void> hideMarkerInfoWindow(MarkerId id) => _state._setInfoWindow(id, false);

  @override
  Future<bool> isMarkerInfoWindowShown(MarkerId id) async => _state._openInfo.contains(id);
}

/// Mappls map that accepts the same declarative markers and polylines as Google Maps.
class MapplsView extends StatefulWidget {
  const MapplsView({
    super.key,
    required this.initialCameraPosition,
    this.markers = const <Marker>{},
    this.polylines = const <Polyline>{},
    this.onMapCreated,
    this.onCameraMove,
    this.onCameraIdle,
    this.onTap,
    this.onLongPress,
    this.myLocationEnabled = false,
    this.myLocationButtonEnabled = true,
    this.zoomControlsEnabled = true,
    this.compassEnabled = true,
    this.mapToolbarEnabled = true,
    this.trafficEnabled = false,
    this.rotateGesturesEnabled = true,
    this.scrollGesturesEnabled = true,
    this.zoomGesturesEnabled = true,
    this.tiltGesturesEnabled = true,
    this.padding = EdgeInsets.zero,
    this.gestureRecognizers,
  });

  final CameraPosition initialCameraPosition;
  final Set<Marker> markers;
  final Set<Polyline> polylines;
  final void Function(MapplsViewController controller)? onMapCreated;
  final void Function(CameraPosition position)? onCameraMove;
  final VoidCallback? onCameraIdle;
  final void Function(LatLng position)? onTap;
  final void Function(LatLng position)? onLongPress;
  final bool myLocationEnabled;
  final bool myLocationButtonEnabled;
  final bool zoomControlsEnabled;
  final bool compassEnabled;
  final bool mapToolbarEnabled;
  final bool trafficEnabled;
  final bool rotateGesturesEnabled;
  final bool scrollGesturesEnabled;
  final bool zoomGesturesEnabled;
  final bool tiltGesturesEnabled;
  final EdgeInsets padding;
  final Set<Factory<OneSequenceGestureRecognizer>>? gestureRecognizers;

  @override
  State<MapplsView> createState() => _MapplsViewState();
}

class _MapplsViewState extends State<MapplsView> {
  m.MapplsMapController? _map;
  _MapplsNativeController? _view;
  bool _styleReady = false;
  bool _settingsReady = AppConfig.settings.isNotEmpty;

  @override
  void initState() {
    super.initState();
    AppConfig.loadAppSettings().whenComplete(() {
      if (mounted) setState(() => _settingsReady = true);
    });
  }

  final Map<MarkerId, Marker> _shownMarkers = <MarkerId, Marker>{};
  final Map<MarkerId, m.Symbol> _symbols = <MarkerId, m.Symbol>{};
  final Map<String, MarkerId> _symbolOwners = <String, MarkerId>{};
  final Set<MarkerId> _openInfo = <MarkerId>{};
  final Map<PolylineId, Polyline> _shownLines = <PolylineId, Polyline>{};
  final Map<PolylineId, m.Line> _lines = <PolylineId, m.Line>{};
  final Set<String> _images = <String>{};

  Future<void> _queue = Future<void>.value();
  bool _syncScheduled = false;

  @override
  void didUpdateWidget(covariant MapplsView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_styleReady) return;
    if (oldWidget.padding != widget.padding) {
      unawaited(_map?.updateContentInsets(widget.padding));
    }
    if (oldWidget.trafficEnabled != widget.trafficEnabled) {
      unawaited(_map?.enableTraffic(widget.trafficEnabled));
    }
    _scheduleSync();
  }

  @override
  void dispose() {
    final map = _map;
    if (map != null) {
      map.onSymbolTapped.remove(_onSymbolTapped);
      map.removeListener(_onCameraChanged);
    }
    super.dispose();
  }

  void _onMapCreated(m.MapplsMapController controller) {
    _map = controller;
    controller.onSymbolTapped.add(_onSymbolTapped);
    if (widget.onCameraMove != null) {
      controller.addListener(_onCameraChanged);
    }
  }

  Future<void> _onStyleLoaded() async {
    final map = _map;
    if (map == null || !mounted) return;
    _styleReady = true;
    _images.clear();
    _symbols.clear();
    _symbolOwners.clear();
    _shownMarkers.clear();
    _lines.clear();
    _shownLines.clear();
    try {
      await map.setSymbolIconAllowOverlap(true);
      await map.setSymbolIconIgnorePlacement(true);
      await map.setSymbolTextAllowOverlap(true);
      if (widget.padding != EdgeInsets.zero) {
        await map.updateContentInsets(widget.padding);
      }
      if (widget.trafficEnabled) {
        await map.enableTraffic(true);
      }
    } catch (_) {}
    _scheduleSync();
    final view = _view ??= _MapplsNativeController(map, this);
    widget.onMapCreated?.call(view);
  }

  void _onCameraChanged() {
    final map = _map;
    final cb = widget.onCameraMove;
    if (map == null || cb == null || !map.isCameraMoving) return;
    final pos = map.cameraPosition;
    if (pos != null) cb(pos);
  }

  void _onCameraIdle() {
    final pos = _map?.cameraPosition;
    if (pos != null) widget.onCameraMove?.call(pos);
    widget.onCameraIdle?.call();
  }

  void _onSymbolTapped(m.Symbol symbol) {
    final id = _symbolOwners[symbol.id];
    if (id == null) return;
    final marker = _shownMarkers[id];
    if (marker == null) return;
    marker.onTap?.call();
    if (marker.infoWindow.label != null) {
      unawaited(_setInfoWindow(id, !_openInfo.contains(id)));
    }
  }

  Future<void> _setInfoWindow(MarkerId id, bool open) async {
    if (open) {
      _openInfo.add(id);
    } else {
      _openInfo.remove(id);
    }
    final marker = _shownMarkers[id];
    final symbol = _symbols[id];
    final map = _map;
    if (marker == null || symbol == null || map == null) return;
    _enqueue(() => map.updateSymbol(symbol, _symbolOptions(marker)));
  }

  void _scheduleSync() {
    if (_syncScheduled) return;
    _syncScheduled = true;
    _enqueue(() async {
      _syncScheduled = false;
      await _syncMarkers();
      await _syncLines();
    });
  }

  void _enqueue(Future<void> Function() task) {
    _queue = _queue.then((_) async {
      if (!mounted || _map == null || !_styleReady) return;
      try {
        await task();
      } catch (e) {
        debugPrint('MapplsView sync failed: $e');
      }
    });
  }

  Future<void> _syncMarkers() async {
    final map = _map!;
    final wanted = <MarkerId, Marker>{
      for (final marker in widget.markers)
        if (marker.visible) marker.markerId: marker,
    };

    for (final id in _shownMarkers.keys.toList()) {
      if (wanted.containsKey(id)) continue;
      final symbol = _symbols.remove(id);
      _shownMarkers.remove(id);
      _openInfo.remove(id);
      if (symbol != null) {
        _symbolOwners.remove(symbol.id);
        await map.removeSymbol(symbol);
      }
    }

    for (final entry in wanted.entries) {
      final marker = entry.value;
      final previous = _shownMarkers[entry.key];
      final symbol = _symbols[entry.key];
      if (previous != null && symbol != null) {
        _shownMarkers[entry.key] = marker;
        if (previous._sameLook(marker)) continue;
        await _ensureImage(marker.icon);
        await map.updateSymbol(symbol, _symbolOptions(marker));
        continue;
      }
      await _ensureImage(marker.icon);
      final added = await map.addSymbol(_symbolOptions(marker));
      _symbols[entry.key] = added;
      _symbolOwners[added.id] = entry.key;
      _shownMarkers[entry.key] = marker;
    }
  }

  Future<void> _syncLines() async {
    final map = _map!;
    final wanted = <PolylineId, Polyline>{
      for (final line in widget.polylines)
        if (line.visible && line.points.length >= 2) line.polylineId: line,
    };

    for (final id in _shownLines.keys.toList()) {
      if (wanted.containsKey(id)) continue;
      final line = _lines.remove(id);
      _shownLines.remove(id);
      if (line != null) await map.removeLine(line);
    }

    final ordered = wanted.values.toList()..sort((a, b) => a.zIndex.compareTo(b.zIndex));
    for (final polyline in ordered) {
      final previous = _shownLines[polyline.polylineId];
      final line = _lines[polyline.polylineId];
      if (previous != null && line != null) {
        _shownLines[polyline.polylineId] = polyline;
        if (previous._sameLook(polyline)) continue;
        await map.updateLine(line, _lineOptions(polyline));
        continue;
      }
      final added = await map.addLine(_lineOptions(polyline));
      _lines[polyline.polylineId] = added;
      _shownLines[polyline.polylineId] = polyline;
    }
  }

  m.SymbolOptions _symbolOptions(Marker marker) {
    final label = _openInfo.contains(marker.markerId) ? marker.infoWindow.label : null;
    return m.SymbolOptions(
      geometry: marker.position,
      iconImage: marker.icon.imageName,
      iconAnchor: _anchorName(marker.anchor),
      iconRotate: marker.rotation,
      iconOpacity: marker.alpha,
      zIndex: marker.zIndex.round(),
      textField: label ?? '',
      textSize: 12,
      textColor: '#111827',
      textHaloColor: '#FFFFFF',
      textHaloWidth: 1.5,
      textAnchor: 'bottom',
      textOffset: const Offset(0, -3.4),
    );
  }

  m.LineOptions _lineOptions(Polyline polyline) {
    return m.LineOptions(
      geometry: polyline.points,
      lineColor: _hex(polyline.color),
      lineOpacity: polyline.color.a,
      lineWidth: polyline.width.toDouble(),
      lineJoin: 'round',
    );
  }

  static String _anchorName(Offset anchor) {
    final vertical = anchor.dy >= 0.75 ? 'bottom' : (anchor.dy <= 0.25 ? 'top' : '');
    final horizontal = anchor.dx >= 0.75 ? 'right' : (anchor.dx <= 0.25 ? 'left' : '');
    if (vertical.isEmpty && horizontal.isEmpty) return 'center';
    if (vertical.isEmpty) return horizontal;
    if (horizontal.isEmpty) return vertical;
    return '$vertical-$horizontal';
  }

  static String _hex(Color color) {
    String two(double v) => (v * 255).round().clamp(0, 255).toRadixString(16).padLeft(2, '0');
    return '#${two(color.r)}${two(color.g)}${two(color.b)}';
  }

  Future<void> _ensureImage(BitmapDescriptor icon) async {
    final name = icon.imageName;
    if (_images.contains(name)) return;
    final bytes = icon.bytes ?? await _pinBytes(icon.hue ?? 0);
    await _map!.addImage(name, bytes);
    _images.add(name);
  }

  static final Map<int, Uint8List> _pinCache = <int, Uint8List>{};

  static Future<Uint8List> _pinBytes(double hue) async {
    final key = hue.round();
    final cached = _pinCache[key];
    if (cached != null) return cached;

    const width = 54.0;
    const height = 72.0;
    final color = HSVColor.fromAHSV(1, hue, 0.85, 0.92).toColor();
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    const center = Offset(width / 2, width / 2);
    const radius = width / 2 - 3;

    final path = Path()
      ..moveTo(width / 2, height - 2)
      ..quadraticBezierTo(width * 0.12, width * 0.82, center.dx - radius, center.dy)
      ..arcTo(Rect.fromCircle(center: center, radius: radius), math.pi, math.pi, false)
      ..quadraticBezierTo(width * 0.88, width * 0.82, width / 2, height - 2)
      ..close();

    canvas.drawPath(path.shift(const Offset(0, 1.5)), Paint()..color = const Color(0x33000000));
    canvas.drawPath(path, Paint()..color = color);
    canvas.drawPath(
      path,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5,
    );
    canvas.drawCircle(center, radius * 0.38, Paint()..color = Colors.white);

    final image = await recorder.endRecording().toImage(width.toInt(), height.toInt());
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    final bytes = data!.buffer.asUint8List();
    _pinCache[key] = bytes;
    return bytes;
  }

  Future<void> _goToMyLocation() async {
    final map = _map;
    if (map == null) return;
    try {
      final here = await map.requestMyLocationLatLng();
      if (here == null) return;
      final zoom = math.max(map.cameraPosition?.zoom ?? 15, 15.0);
      await map.animateCamera(m.CameraUpdate.newLatLngZoom(here, zoom));
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    if (!_settingsReady) {
      return ColoredBox(color: Theme.of(context).colorScheme.surface);
    }

    if (AppConfig.useGoogleMap) {
      return GoogleMapView(
        initialCameraPosition: widget.initialCameraPosition,
        markers: widget.markers,
        polylines: widget.polylines,
        onMapCreated: widget.onMapCreated,
        onCameraMove: widget.onCameraMove,
        onCameraIdle: widget.onCameraIdle,
        onTap: widget.onTap,
        onLongPress: widget.onLongPress,
        myLocationEnabled: widget.myLocationEnabled,
        myLocationButtonEnabled: widget.myLocationButtonEnabled,
        zoomControlsEnabled: widget.zoomControlsEnabled,
        compassEnabled: widget.compassEnabled,
        mapToolbarEnabled: widget.mapToolbarEnabled,
        trafficEnabled: widget.trafficEnabled,
        rotateGesturesEnabled: widget.rotateGesturesEnabled,
        scrollGesturesEnabled: widget.scrollGesturesEnabled,
        zoomGesturesEnabled: widget.zoomGesturesEnabled,
        tiltGesturesEnabled: widget.tiltGesturesEnabled,
        padding: widget.padding,
        gestureRecognizers: widget.gestureRecognizers,
      );
    }

    final map = m.MapplsMap(
      initialCameraPosition: widget.initialCameraPosition,
      onMapCreated: _onMapCreated,
      onStyleLoadedCallback: _onStyleLoaded,
      onCameraIdle: _onCameraIdle,
      trackCameraPosition: widget.onCameraMove != null,
      myLocationEnabled: widget.myLocationEnabled,
      compassEnabled: widget.compassEnabled,
      rotateGesturesEnabled: widget.rotateGesturesEnabled,
      scrollGesturesEnabled: widget.scrollGesturesEnabled,
      zoomGesturesEnabled: widget.zoomGesturesEnabled,
      tiltGesturesEnabled: widget.tiltGesturesEnabled,
      gestureRecognizers: widget.gestureRecognizers,
      onMapClick: widget.onTap == null ? null : (_, latLng) => widget.onTap!(latLng),
      onMapLongClick: widget.onLongPress == null ? null : (_, latLng) => widget.onLongPress!(latLng),
    );

    if (!(widget.myLocationEnabled && widget.myLocationButtonEnabled)) return map;

    return Stack(
      children: [
        Positioned.fill(child: map),
        Positioned(
          right: 12 + widget.padding.right,
          bottom: 96 + widget.padding.bottom,
          child: Material(
            color: Theme.of(context).colorScheme.surface,
            shape: const CircleBorder(),
            elevation: 3,
            child: IconButton(
              tooltip: 'My location',
              icon: Icon(Icons.my_location, color: Theme.of(context).colorScheme.onSurface),
              onPressed: _goToMyLocation,
            ),
          ),
        ),
      ],
    );
  }
}
