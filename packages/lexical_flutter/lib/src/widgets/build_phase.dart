/// Doing something safely while the framework is building.
library;

import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

/// Whether the framework is building widgets at this moment.
///
/// A commit can land **during a build** — and not as an exotic case. Every
/// `initState` runs inside one, and registering behaviour, seeding an empty
/// document or the first reconcile all commit. Anything a commit listener does
/// that marks a widget dirty — `setState`, inserting an `OverlayEntry` — is
/// then an error, and a loud one:
///
/// > setState() or markNeedsBuild() called during build.
///
/// Two things have to be checked, because either alone misses a real case:
///
/// * the **scheduler phase**, which catches commits inside a frame;
/// * the framework's own `debugBuilding`, which catches the build `runApp`
///   performs synchronously *outside* any frame — the very first build an
///   application does, with the phase still `idle`.
///
/// `debugBuilding` exists only in debug, which is also the only mode where the
/// assertion it prevents exists. In release, marking a widget dirty during a
/// build is not fatal: the element is rebuilt in this pass or the next one.
bool get isBuildingWidgets {
  final phase = SchedulerBinding.instance.schedulerPhase;
  if (phase == SchedulerPhase.persistentCallbacks ||
      phase == SchedulerPhase.midFrameMicrotasks) {
    return true;
  }
  var building = false;
  assert(() {
    building = WidgetsBinding.instance.buildOwner?.debugBuilding ?? false;
    return true;
  }());
  return building;
}

/// Runs [action] now, or at the end of the frame if a build is in progress.
///
/// The tool for anything a commit listener does that touches the widget tree.
/// Use it instead of `setState` in an update listener:
///
/// ```dart
/// editor.registerUpdateListener((_) {
///   whenBuildIsDone(() {
///     if (mounted) setState(() {});
///   });
/// });
/// ```
///
/// `LexicalBuilder` already does this, and is the better answer when all you
/// need is a widget that follows the document.
void whenBuildIsDone(VoidCallback action) {
  if (!isBuildingWidgets) {
    action();
    return;
  }
  SchedulerBinding.instance.addPostFrameCallback((_) => action());
  // A build outside a frame has no end-of-frame to wait for until something
  // asks for one.
  SchedulerBinding.instance.ensureVisualUpdate();
}
