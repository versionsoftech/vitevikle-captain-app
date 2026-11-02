import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart' as g;

import 'mappls_map.dart';

g.LatLng _toG(LatLng p) => g.LatLng(p.latitude, p.longitude);

g.LatLngBounds _toGBounds(LatLngBounds b) => g.LatLngBounds(
      southwest: _toG(b.southwest),
      northeast: _toG(b.northeast),
    );

g.CameraPosition _toGCamera(CameraPosition p) => g.CameraPosition(
      target: _toG(p.target),
      zoom: p.zoom,
      bearing: p.bearing,
      tilt: p.tilt,
    );

LatLng _fromG(g.LatLng p) => LatLng(p.latitude, p.longitude);

LatLngBounds _fromGBounds(g.LatLngBounds b) => LatLngBounds(
      southwest: _fromG(b.southwest),
      northeast: _fromG(b.northeast),
    );

class GoogleMapViewController extends MapplsViewController {
  GoogleMapViewController._(this._map);

  final g.GoogleMapController _map;

  @override
  Future<void> animateCamera(CameraUpdate update, {Duration? duration}) async {
    await _map.animateCamera(update.toGoogle());
  }

  @override
  Future<void> moveCamera(CameraUpdate update) async {
    await _map.moveCamera(update.toGoogle());
  }

  @override
  Future<LatLngBounds> getVisibleRegion() async => _fromGBounds(await _map.getVisibleRegion());

  @override
  Future<double> getZoomLevel() => _map.getZoomLevel();

  @override
  Future<void> showMarkerInfoWindow(MarkerId id) => _map.showMarkerInfoWindow(g.MarkerId(id.value));

  @override
  Future<void> hideMarkerInfoWindow(MarkerId id) => _map.hideMarkerInfoWindow(g.MarkerId(id.value));

  @override
  Future<bool> isMarkerInfoWindowShown(MarkerId id) => _map.isMarkerInfoWindowShown(g.MarkerId(id.value));
}

/// Google Maps widget with the same declarative API as [MapplsView].
class GoogleMapView extends StatelessWidget {
  const GoogleMapView({
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

  Set<g.Marker> get _gMarkers => markers
      .map(
        (m) => g.Marker(
          markerId: g.MarkerId(m.markerId.value),
          position: _toG(m.position),
          icon: m.icon.bytes != null
              ? g.BitmapDescriptor.fromBytes(m.icon.bytes!)
              : (m.icon.hue != null
                  ? g.BitmapDescriptor.defaultMarkerWithHue(m.icon.hue!)
                  : g.BitmapDescriptor.defaultMarker),
          infoWindow: g.InfoWindow(title: m.infoWindow.title, snippet: m.infoWindow.snippet),
          anchor: m.anchor,
          rotation: m.rotation,
          alpha: m.alpha,
          flat: m.flat,
          visible: m.visible,
          zIndex: m.zIndex,
          draggable: m.draggable,
          consumeTapEvents: m.consumeTapEvents,
          onTap: m.onTap,
        ),
      )
      .toSet();

  Set<g.Polyline> get _gPolylines => polylines
      .map(
        (p) => g.Polyline(
          polylineId: g.PolylineId(p.polylineId.value),
          points: p.points.map(_toG).toList(growable: false),
          color: p.color,
          width: p.width,
          visible: p.visible,
          zIndex: p.zIndex,
          consumeTapEvents: p.consumeTapEvents,
          onTap: p.onTap,
        ),
      )
      .toSet();

  @override
  Widget build(BuildContext context) {
    return g.GoogleMap(
      initialCameraPosition: _toGCamera(initialCameraPosition),
      markers: _gMarkers,
      polylines: _gPolylines,
      onMapCreated: (controller) {
        onMapCreated?.call(GoogleMapViewController._(controller));
      },
      onCameraMove: onCameraMove == null
          ? null
          : (pos) => onCameraMove!(
                CameraPosition(
                  target: _fromG(pos.target),
                  zoom: pos.zoom,
                  bearing: pos.bearing,
                  tilt: pos.tilt,
                ),
              ),
      onCameraIdle: onCameraIdle,
      onTap: onTap == null ? null : (p) => onTap!(_fromG(p)),
      onLongPress: onLongPress == null ? null : (p) => onLongPress!(_fromG(p)),
      myLocationEnabled: myLocationEnabled,
      myLocationButtonEnabled: myLocationButtonEnabled,
      zoomControlsEnabled: zoomControlsEnabled,
      compassEnabled: compassEnabled,
      mapToolbarEnabled: mapToolbarEnabled,
      trafficEnabled: trafficEnabled,
      rotateGesturesEnabled: rotateGesturesEnabled,
      scrollGesturesEnabled: scrollGesturesEnabled,
      zoomGesturesEnabled: zoomGesturesEnabled,
      tiltGesturesEnabled: tiltGesturesEnabled,
      padding: padding,
      gestureRecognizers:
          gestureRecognizers ?? const <Factory<OneSequenceGestureRecognizer>>{},
    );
  }
}
