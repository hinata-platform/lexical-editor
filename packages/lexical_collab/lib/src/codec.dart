/// The bytes an update is made of.
///
/// Unsigned LEB128 for every number and a length-prefixed UTF-8 blob for every
/// string. Small integers cost one byte, which matters: an update is often a
/// single keystroke, and a fixed-width encoding would spend more bytes on the
/// frame than on the character.
library;

import 'dart:convert';
import 'dart:typed_data';

/// Raised when an update cannot be decoded.
///
/// An update arrives from the network, so it is untrusted input. Every read
/// is bounds-checked and every failure lands here rather than as a range
/// error from somewhere deep inside the parser.
final class CollabDecodeException implements Exception {
  /// Records why decoding stopped.
  const CollabDecodeException(this.message);

  /// What went wrong.
  final String message;

  @override
  String toString() => 'CollabDecodeException: $message';
}

/// Builds the byte form of an update.
final class ByteWriter {
  final BytesBuilder _bytes = BytesBuilder(copy: false);

  /// Appends an unsigned LEB128 integer.
  void uint(int value) {
    if (value < 0) {
      throw ArgumentError.value(value, 'value', 'must not be negative');
    }
    var rest = value;
    while (rest >= 0x80) {
      _bytes.addByte((rest & 0x7f) | 0x80);
      rest >>= 7;
    }
    _bytes.addByte(rest);
  }

  /// Appends one raw byte.
  void byte(int value) => _bytes.addByte(value & 0xff);

  /// Appends a length-prefixed UTF-8 string.
  void string(String value) {
    final encoded = utf8.encode(value);
    uint(encoded.length);
    _bytes.add(encoded);
  }

  /// The bytes written so far.
  Uint8List toBytes() => _bytes.toBytes();
}

/// Reads the byte form of an update.
final class ByteReader {
  /// Reads from [_data].
  ByteReader(this._data);

  final Uint8List _data;
  int _offset = 0;

  /// Whether any bytes are left.
  bool get hasMore => _offset < _data.length;

  /// Reads an unsigned LEB128 integer.
  int uint() {
    var result = 0;
    var shift = 0;
    while (true) {
      if (_offset >= _data.length) {
        throw const CollabDecodeException('truncated integer');
      }
      // Ten groups of seven bits already exceed a 64-bit integer; anything
      // longer is a malformed or hostile stream rather than a large number.
      if (shift > 63) {
        throw const CollabDecodeException('integer too long');
      }
      final byte = _data[_offset++];
      result |= (byte & 0x7f) << shift;
      if (byte < 0x80) return result;
      shift += 7;
    }
  }

  /// Reads one raw byte.
  int byte() {
    if (_offset >= _data.length) {
      throw const CollabDecodeException('truncated byte');
    }
    return _data[_offset++];
  }

  /// Reads a length-prefixed UTF-8 string.
  String string() {
    final length = uint();
    if (_offset + length > _data.length) {
      throw const CollabDecodeException('truncated string');
    }
    final value = utf8.decode(
      _data.sublist(_offset, _offset + length),
      allowMalformed: true,
    );
    _offset += length;
    return value;
  }
}
