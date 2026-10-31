/// Reading and resolving a `grid-template-columns` value.
library;

/// How a [LayoutTrack] is sized.
enum LayoutTrackKind {
  /// A share of the space left over: `1fr`, `2fr`.
  fraction,

  /// A fixed width in pixels: `200px`.
  pixels,

  /// A percentage of the container: `25%`.
  percent,

  /// At most a width in pixels, shrinking to nothing: `minmax(0, 200px)`.
  upTo,

  /// Sized by its content: `auto`. Resolved as `1fr`, the share an
  /// unconstrained column of a mail layout ends up with.
  auto,
}

/// One column of a grid template.
final class LayoutTrack {
  /// Creates a track.
  const LayoutTrack(this.kind, this.value);

  /// A `1fr` track, which every unknown track falls back to.
  static const LayoutTrack oneFraction = LayoutTrack(LayoutTrackKind.fraction, 1);

  /// How the track is sized.
  final LayoutTrackKind kind;

  /// Fractions, pixels or percent, depending on [kind]; `0` for `auto`.
  final double value;

  @override
  bool operator ==(Object other) =>
      other is LayoutTrack && other.kind == kind && other.value == value;

  @override
  int get hashCode => Object.hash(kind, value);

  @override
  String toString() => switch (kind) {
    LayoutTrackKind.fraction => '${value}fr',
    LayoutTrackKind.pixels => '${value}px',
    LayoutTrackKind.percent => '$value%',
    LayoutTrackKind.upTo => 'minmax(0, ${value}px)',
    LayoutTrackKind.auto => 'auto',
  };
}

/// The most columns a template is read as.
const int maxLayoutTracks = 16;

/// The longest template string that is read.
const int maxTemplateLength = 256;

/// The widest a fixed track is taken to be, in pixels.
const double _maxTrackPixels = 10000;

/// Parses a `grid-template-columns` value into tracks.
///
/// The subset a document carries: space-separated `Nfr`, `Npx`, `N%`, `auto`
/// and `minmax(0, Npx)`. A track that is none of these reads as `1fr`, so a
/// template written by a newer client still lays out as columns rather than
/// collapsing. Bounded — at most [maxLayoutTracks] tracks from at most
/// [maxTemplateLength] characters — and never throws. An empty template
/// answers an empty list.
List<LayoutTrack> parseTemplateColumns(String template) {
  final input = template.trim().toLowerCase();
  if (input.isEmpty) return const [];
  final bounded = input.length > maxTemplateLength
      ? input.substring(0, maxTemplateLength)
      : input;

  // Split on spaces outside parentheses, so `minmax(0, 200px)` is one track.
  final tokens = <String>[];
  final current = StringBuffer();
  var depth = 0;
  for (final char in bounded.split('')) {
    if (char == '(') depth++;
    if (char == ')' && depth > 0) depth--;
    if (depth == 0 && (char == ' ' || char == '\t' || char == '\n')) {
      if (current.isNotEmpty) tokens.add(current.toString());
      current.clear();
      continue;
    }
    current.write(char);
  }
  if (current.isNotEmpty) tokens.add(current.toString());

  return [
    for (final token in tokens.take(maxLayoutTracks)) _track(token),
  ];
}

LayoutTrack _track(String token) {
  if (token == 'auto') return const LayoutTrack(LayoutTrackKind.auto, 0);
  final minmax = RegExp(
    r'^minmax\(\s*0(?:px)?\s*,\s*(\d*\.?\d+)px\s*\)$',
  ).firstMatch(token);
  if (minmax != null) {
    final pixels = double.tryParse(minmax.group(1)!);
    if (pixels != null && pixels.isFinite) {
      return LayoutTrack(
        LayoutTrackKind.upTo,
        pixels.clamp(0, _maxTrackPixels).toDouble(),
      );
    }
  }
  final match = RegExp(r'^(\d*\.?\d+)(fr|px|%)$').firstMatch(token);
  if (match == null) return LayoutTrack.oneFraction;
  final amount = double.tryParse(match.group(1)!);
  if (amount == null || !amount.isFinite) return LayoutTrack.oneFraction;
  return switch (match.group(2)) {
    'fr' => amount <= 0
        ? LayoutTrack.oneFraction
        : LayoutTrack(LayoutTrackKind.fraction, amount.clamp(0, 1000).toDouble()),
    'px' => LayoutTrack(
      LayoutTrackKind.pixels,
      amount.clamp(0, _maxTrackPixels).toDouble(),
    ),
    _ => LayoutTrack(LayoutTrackKind.percent, amount.clamp(0, 100).toDouble()),
  };
}

/// The pixel width below which a layout of [tracks] stacks its columns.
///
/// The sum of the fixed `px` tracks — the width the template cannot do
/// without. A mail built for 600 pixels uses a media query to stack its
/// columns on a phone; this is the same decision made without one.
double minimumTemplateWidth(List<LayoutTrack> tracks) {
  var sum = 0.0;
  for (final track in tracks) {
    if (track.kind == LayoutTrackKind.pixels) sum += track.value;
  }
  return sum;
}

/// Resolves [tracks] against an [available] width, in pixels.
///
/// The column widths, in order, or `null` when the layout should stack
/// instead — [available] is narrower than [minimumTemplateWidth]. [gap] is
/// the space between neighbouring columns.
///
/// The grid algorithm, cut to the subset: fixed and percentage tracks take
/// their size first, `minmax(0, N)` tracks grow up to `N` out of what is left,
/// and fractions (with `auto`, which counts as `1fr`) share the rest. When
/// the fixed tracks already overflow, the fractions get nothing — the CSS
/// answer, kept so a template means the same thing everywhere.
List<double>? resolveTemplateColumns(
  List<LayoutTrack> tracks,
  double available, {
  double gap = 0,
}) {
  if (tracks.isEmpty) return const [];
  if (!available.isFinite || available < 0) return null;
  if (available < minimumTemplateWidth(tracks)) return null;

  final widths = List<double>.filled(tracks.length, 0);
  var remaining = available - gap * (tracks.length - 1);
  var fractions = 0.0;
  final upTo = <int>[];

  for (var i = 0; i < tracks.length; i++) {
    final track = tracks[i];
    switch (track.kind) {
      case LayoutTrackKind.pixels:
        widths[i] = track.value;
        remaining -= track.value;
      case LayoutTrackKind.percent:
        widths[i] = available * track.value / 100;
        remaining -= widths[i];
      case LayoutTrackKind.upTo:
        upTo.add(i);
      case LayoutTrackKind.fraction:
        fractions += track.value;
      case LayoutTrackKind.auto:
        fractions += 1;
    }
  }

  if (upTo.isNotEmpty) {
    // Equal shares, each capped at its maximum. Visiting the smallest caps
    // first hands what a capped track leaves over to the larger ones.
    upTo.sort((a, b) => tracks[a].value.compareTo(tracks[b].value));
    var pool = remaining > 0 ? remaining : 0.0;
    var left = upTo.length;
    for (final i in upTo) {
      final share = pool / left;
      widths[i] = tracks[i].value < share ? tracks[i].value : share;
      pool -= widths[i];
      remaining -= widths[i];
      left--;
    }
  }

  if (fractions > 0) {
    final free = remaining > 0 ? remaining : 0.0;
    for (var i = 0; i < tracks.length; i++) {
      final track = tracks[i];
      final weight = switch (track.kind) {
        LayoutTrackKind.fraction => track.value,
        LayoutTrackKind.auto => 1.0,
        _ => 0.0,
      };
      if (weight > 0) widths[i] = free * weight / fractions;
    }
  }
  return widths;
}
