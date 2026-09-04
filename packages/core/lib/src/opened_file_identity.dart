import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

/// Captures and verifies the operating-system object behind an opened file.
///
/// Path validation alone is insufficient because another process can replace
/// the checked path before [File.open] runs. This evidence binds the resulting
/// handle to both the object and canonical path that were checked beforehand.
final class OpenedFileIdentity {
  const OpenedFileIdentity._(
    this._expectedPath,
    this._expectedIdentity,
    this._validationHandle,
  );

  final String _expectedPath;
  final String _expectedIdentity;
  final int _validationHandle;

  static Future<OpenedFileIdentity> capturePath(String path) async {
    if (Platform.isWindows) return _captureWindowsPath(path);
    if (Platform.isMacOS || Platform.isLinux) {
      return _capturePosixPath(path);
    }
    throw UnsupportedError(
      'Opened-file identity is unsupported on ${Platform.operatingSystem}.',
    );
  }

  Future<void> verify(RandomAccessFile file) async {
    if (Platform.isWindows) {
      if (_windowsHandleIdentity(_validationHandle) != _expectedIdentity ||
          !_samePath(_windowsHandlePath(_validationHandle), _expectedPath)) {
        throw FileSystemException(
          'Opened file changed after path validation',
          _expectedPath,
        );
      }
      return;
    }

    final descriptor = _descriptor(file);
    final actualIdentity = Platform.isMacOS
        ? _macDescriptorIdentity(descriptor)
        : Platform.isLinux
        ? _linuxDescriptorIdentity(descriptor)
        : throw UnsupportedError(
            'Opened-file identity is unsupported on '
            '${Platform.operatingSystem}.',
          );
    final actualPath = await _descriptorPath(descriptor);
    if (actualIdentity != _expectedIdentity ||
        !_samePath(actualPath, _expectedPath)) {
      throw FileSystemException(
        'Opened file changed after path validation',
        _expectedPath,
      );
    }
  }

  void close() {
    if (Platform.isWindows) {
      _closeHandle()(_validationHandle);
    } else {
      _closeDescriptor()(_validationHandle);
    }
  }

  // RandomAccessFile does not expose its descriptor in the public interface,
  // but the VM implementation supplies this fail-closed getter on every native
  // platform.
  static int _descriptor(RandomAccessFile file) {
    try {
      final descriptor = (file as dynamic).fd;
      if (descriptor is int && descriptor >= 0) return descriptor;
    } on Object {
      // Report one stable error below if the VM representation ever changes.
    }
    throw FileSystemException('Cannot inspect opened file handle');
  }

  static Future<String> _descriptorPath(int descriptor) async {
    if (Platform.isLinux) {
      return File('/proc/self/fd/$descriptor').resolveSymbolicLinks();
    }
    if (Platform.isMacOS) return _macDescriptorPath(descriptor);
    throw UnsupportedError(
      'Opened-file paths are unsupported on ${Platform.operatingSystem}.',
    );
  }

  static bool _samePath(String left, String right) {
    if (!Platform.isWindows) return left == right;
    return _normalizeWindowsPath(left) == _normalizeWindowsPath(right);
  }
}

Future<OpenedFileIdentity> _capturePosixPath(String path) async {
  final pointer = path.toNativeUtf8();
  int? descriptor;
  try {
    descriptor = _openDescriptor()(pointer, 0);
    if (descriptor < 0) {
      throw FileSystemException('Cannot inspect validated file', path);
    }
    final identity = Platform.isMacOS
        ? _macDescriptorIdentity(descriptor)
        : _linuxDescriptorIdentity(descriptor);
    final actualPath = await OpenedFileIdentity._descriptorPath(descriptor);
    if (!OpenedFileIdentity._samePath(actualPath, path)) {
      throw FileSystemException('Validated file changed while opening', path);
    }
    return OpenedFileIdentity._(path, identity, descriptor);
  } on Object {
    if (descriptor != null && descriptor >= 0) {
      _closeDescriptor()(descriptor);
    }
    rethrow;
  } finally {
    calloc.free(pointer);
  }
}

String _macDescriptorIdentity(int descriptor) {
  final value = calloc<_MacStat>();
  try {
    final result = _macFstat()(descriptor, value);
    if (result != 0) {
      throw FileSystemException('Cannot inspect opened file handle');
    }
    return '${value.ref.device}:${value.ref.inode}';
  } finally {
    calloc.free(value);
  }
}

String _macDescriptorPath(int descriptor) {
  const fGetPath = 50;
  final buffer = calloc<Uint8>(4096);
  try {
    final fcntl = DynamicLibrary.process()
        .lookupFunction<
          Int32 Function(Int32, Int32, VarArgs<(Pointer<Uint8>,)>),
          int Function(int, int, Pointer<Uint8>)
        >('fcntl');
    if (fcntl(descriptor, fGetPath, buffer) != 0) {
      throw FileSystemException('Cannot resolve opened file path');
    }
    return buffer.cast<Utf8>().toDartString();
  } finally {
    calloc.free(buffer);
  }
}

_MacFstatDart _macFstat() {
  final library = DynamicLibrary.process();
  try {
    return library.lookupFunction<_MacFstatNative, _MacFstatDart>(
      r'fstat$INODE64',
    );
  } on ArgumentError {
    return library.lookupFunction<_MacFstatNative, _MacFstatDart>('fstat');
  }
}

String _linuxDescriptorIdentity(int descriptor) {
  final value = calloc<_LinuxStat>();
  try {
    final fstat = DynamicLibrary.process()
        .lookupFunction<_LinuxFstatNative, _LinuxFstatDart>('fstat');
    if (fstat(descriptor, value) != 0) {
      throw FileSystemException('Cannot inspect opened file handle');
    }
    return '${value.ref.device}:${value.ref.inode}';
  } finally {
    calloc.free(value);
  }
}

OpenedFileIdentity _captureWindowsPath(String path) {
  final pointer = path.toNativeUtf16();
  int? handle;
  try {
    // Keeping this handle open without FILE_SHARE_DELETE makes replacement of
    // the validated file fail until the Dart handle has been opened. This
    // avoids depending on the VM's private CRT descriptor representation.
    handle = _createFile()(pointer, 0, 3, 0, 3, 0x02000000, 0);
    if (handle == -1) {
      throw FileSystemException('Cannot inspect validated file', path);
    }
    final identity = _windowsHandleIdentity(handle);
    final actualPath = _windowsHandlePath(handle);
    if (!OpenedFileIdentity._samePath(actualPath, path)) {
      throw FileSystemException('Validated file changed while opening', path);
    }
    return OpenedFileIdentity._(path, identity, handle);
  } on Object {
    if (handle != null && handle != -1) _closeHandle()(handle);
    rethrow;
  } finally {
    calloc.free(pointer);
  }
}

String _windowsHandleIdentity(int handle) {
  final value = calloc<_WindowsFileInformation>();
  try {
    if (_getFileInformationByHandle()(handle, value) == 0) {
      throw FileSystemException('Cannot inspect opened file handle');
    }
    return '${value.ref.volumeSerialNumber.toRadixString(16).padLeft(8, '0')}:'
        '${value.ref.fileIndexHigh.toRadixString(16).padLeft(8, '0')}'
        '${value.ref.fileIndexLow.toRadixString(16).padLeft(8, '0')}';
  } finally {
    calloc.free(value);
  }
}

String _windowsHandlePath(int handle) {
  final buffer = calloc<Uint16>(32768);
  try {
    final length = _getFinalPathNameByHandle()(handle, buffer, 32768, 0);
    if (length == 0 || length >= 32768) {
      throw FileSystemException('Cannot resolve opened file path');
    }
    return buffer.cast<Utf16>().toDartString(length: length);
  } finally {
    calloc.free(buffer);
  }
}

String _normalizeWindowsPath(String path) {
  var normalized = path.replaceAll('/', r'\');
  if (normalized.startsWith(r'\\?\UNC\')) {
    normalized = r'\\' + normalized.substring(8);
  } else if (normalized.startsWith(r'\\?\')) {
    normalized = normalized.substring(4);
  }
  while (normalized.length > 3 && normalized.endsWith(r'\')) {
    normalized = normalized.substring(0, normalized.length - 1);
  }
  return normalized.toLowerCase();
}

_CreateFileDart _createFile() =>
    _kernel32.lookupFunction<_CreateFileNative, _CreateFileDart>('CreateFileW');

_CloseHandleDart _closeHandle() => _kernel32
    .lookupFunction<_CloseHandleNative, _CloseHandleDart>('CloseHandle');

_OpenDescriptorDart _openDescriptor() => DynamicLibrary.process()
    .lookupFunction<_OpenDescriptorNative, _OpenDescriptorDart>('open');

_CloseDescriptorDart _closeDescriptor() => DynamicLibrary.process()
    .lookupFunction<_CloseDescriptorNative, _CloseDescriptorDart>('close');

_GetFileInformationDart _getFileInformationByHandle() => _kernel32
    .lookupFunction<_GetFileInformationNative, _GetFileInformationDart>(
      'GetFileInformationByHandle',
    );

_GetFinalPathDart _getFinalPathNameByHandle() =>
    _kernel32.lookupFunction<_GetFinalPathNative, _GetFinalPathDart>(
      'GetFinalPathNameByHandleW',
    );

final DynamicLibrary _kernel32 = Platform.isWindows
    ? DynamicLibrary.open('kernel32.dll')
    : DynamicLibrary.process();

typedef _MacFstatNative = Int32 Function(Int32, Pointer<_MacStat>);
typedef _MacFstatDart = int Function(int, Pointer<_MacStat>);
typedef _LinuxFstatNative = Int32 Function(Int32, Pointer<_LinuxStat>);
typedef _LinuxFstatDart = int Function(int, Pointer<_LinuxStat>);
typedef _OpenDescriptorNative = Int32 Function(Pointer<Utf8>, Int32);
typedef _OpenDescriptorDart = int Function(Pointer<Utf8>, int);
typedef _CloseDescriptorNative = Int32 Function(Int32);
typedef _CloseDescriptorDart = int Function(int);
typedef _CreateFileNative =
    IntPtr Function(
      Pointer<Utf16>,
      Uint32,
      Uint32,
      IntPtr,
      Uint32,
      Uint32,
      IntPtr,
    );
typedef _CreateFileDart =
    int Function(Pointer<Utf16>, int, int, int, int, int, int);
typedef _CloseHandleNative = Int32 Function(IntPtr);
typedef _CloseHandleDart = int Function(int);
typedef _GetFileInformationNative =
    Int32 Function(IntPtr, Pointer<_WindowsFileInformation>);
typedef _GetFileInformationDart =
    int Function(int, Pointer<_WindowsFileInformation>);
typedef _GetFinalPathNative =
    Uint32 Function(IntPtr, Pointer<Uint16>, Uint32, Uint32);
typedef _GetFinalPathDart = int Function(int, Pointer<Uint16>, int, int);

final class _MacStat extends Struct {
  @Uint32()
  external int device;

  @Uint16()
  external int mode;

  @Uint16()
  external int links;

  @Uint64()
  external int inode;

  @Uint32()
  external int user;

  @Uint32()
  external int group;

  @Int32()
  external int rawDevice;

  external _MacTimespec accessed;
  external _MacTimespec modified;
  external _MacTimespec changed;
  external _MacTimespec created;

  @Int64()
  external int size;

  @Int64()
  external int blocks;

  @Int32()
  external int blockSize;

  @Uint32()
  external int flags;

  @Uint32()
  external int generation;

  @Int32()
  external int spare;

  @Int64()
  external int reserved0;

  @Int64()
  external int reserved1;
}

final class _MacTimespec extends Struct {
  @Int64()
  external int seconds;

  @Int64()
  external int nanoseconds;
}

final class _LinuxStat extends Struct {
  @Uint64()
  external int device;

  @Uint64()
  external int inode;

  @Uint64()
  external int links;

  @Uint32()
  external int mode;

  @Uint32()
  external int user;

  @Uint32()
  external int group;

  @Int32()
  external int padding;

  @Uint64()
  external int rawDevice;

  @Int64()
  external int size;

  @Int64()
  external int blockSize;

  @Int64()
  external int blocks;

  external _LinuxTimespec accessed;
  external _LinuxTimespec modified;
  external _LinuxTimespec changed;

  @Int64()
  external int reserved0;

  @Int64()
  external int reserved1;

  @Int64()
  external int reserved2;
}

final class _LinuxTimespec extends Struct {
  @Int64()
  external int seconds;

  @Int64()
  external int nanoseconds;
}

final class _WindowsFileInformation extends Struct {
  @Uint32()
  external int attributes;

  @Uint32()
  external int creationTimeLow;

  @Uint32()
  external int creationTimeHigh;

  @Uint32()
  external int accessTimeLow;

  @Uint32()
  external int accessTimeHigh;

  @Uint32()
  external int writeTimeLow;

  @Uint32()
  external int writeTimeHigh;

  @Uint32()
  external int volumeSerialNumber;

  @Uint32()
  external int fileSizeHigh;

  @Uint32()
  external int fileSizeLow;

  @Uint32()
  external int numberOfLinks;

  @Uint32()
  external int fileIndexHigh;

  @Uint32()
  external int fileIndexLow;
}
