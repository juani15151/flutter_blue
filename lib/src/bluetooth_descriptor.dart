// Copyright 2017, Paul DeMarco.
// All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

part of flutter_blue;

class BluetoothDescriptor {
  static final Uuid cccd = Uuid.fromString("00002902-0000-1000-8000-00805f9b34fb");

  final Uuid uuid;
  final DeviceIdentifier deviceId;
  final Uuid serviceUuid; // The service that this descriptor belongs to.
  final BluetoothCharacteristicIdentifier
      characteristicId; // The characteristic that this descriptor belongs to.

  BehaviorSubject<List<int>> _value;
  Stream<List<int>> get value => _value.stream;

  List<int> get lastValue => _value.value;

  BluetoothDescriptor.fromProto(protos.BluetoothDescriptor p)
      : uuid = Uuid.fromString(p.uuid),
        deviceId = new DeviceIdentifier(p.remoteId),
        serviceUuid = Uuid.fromString(p.serviceUuid),
        characteristicId = BluetoothCharacteristicIdentifier.fromProto(p.characteristicId),
        _value = BehaviorSubject.seeded(p.value);

  /// Retrieves the value of a specified descriptor
  Future<List<int>> read() async {
    var request = protos.ReadDescriptorRequest.create()
      ..remoteId = deviceId.toString()
      ..descriptorUuid = uuid.toString()
      ..characteristicUuid = characteristicUuid.toString()
      ..serviceUuid = serviceUuid.toString();

    await FlutterBlue.instance._channel
        .invokeMethod('readDescriptor', request.writeToBuffer());

    return FlutterBlue.instance._methodStream
        .where((m) => m.method == "ReadDescriptorResponse")
        .map((m) => m.arguments)
        .map((buffer) => new protos.ReadDescriptorResponse.fromBuffer(buffer))
        .where((p) =>
            (p.request.remoteId == request.remoteId) &&
            (p.request.descriptorUuid == request.descriptorUuid) &&
            (p.request.characteristicUuid == request.characteristicUuid) &&
            (p.request.serviceUuid == request.serviceUuid))
        .map((d) => d.value)
        .first
        .then((d) {
      _value.add(d);
      return d;
    });
  }

  /// Writes the value of a descriptor
  Future<Null> write(List<int> value) async {
    var request = protos.WriteDescriptorRequest.create()
      ..remoteId = deviceId.toString()
      ..descriptorUuid = uuid.toString()
      ..characteristicUuid = characteristicUuid.toString()
      ..serviceUuid = serviceUuid.toString()
      ..value = value;

    await FlutterBlue.instance._channel
        .invokeMethod('writeDescriptor', request.writeToBuffer());

    return FlutterBlue.instance._methodStream
        .where((m) => m.method == "WriteDescriptorResponse")
        .map((m) => m.arguments)
        .map((buffer) => new protos.WriteDescriptorResponse.fromBuffer(buffer))
        .where((p) =>
            (p.request.remoteId == request.remoteId) &&
            (p.request.descriptorUuid == request.descriptorUuid) &&
            (p.request.characteristicUuid == request.characteristicUuid) &&
            (p.request.serviceUuid == request.serviceUuid))
        .first
        .then((w) => w.success)
        .then((success) => (!success)
            ? throw new Exception('Failed to write the descriptor')
            : null)
        .then((_) => _value.add(value))
        .then((_) => null);
  }
}
