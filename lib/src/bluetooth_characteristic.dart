// Copyright 2017, Paul DeMarco.
// All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

part of flutter_blue;

class BluetoothCharacteristicIdentifier {
  final Uuid uuid;
  final int instanceId;
  final int _hashCode;

  BluetoothCharacteristicIdentifier(Uuid uuid, int instanceId)
      : uuid = uuid,
        instanceId = instanceId,
        _hashCode = _calcHashCode(uuid, instanceId);

  factory BluetoothCharacteristicIdentifier.fromProto(
          protos.BluetoothCharacteristicIdentifier p) =>
      BluetoothCharacteristicIdentifier(Uuid.fromString(p.uuid), p.instanceId);


  @override
  String toString() {
    return """"[UUID "$uuid", InstanceId "$instanceId"]""";
  }

  protos.BluetoothCharacteristicIdentifier get toProto {
    return protos.BluetoothCharacteristicIdentifier.create()
      ..uuid = this.uuid.toString()
      ..instanceId = this.instanceId
    ;
  }

  static int _calcHashCode(Uuid uuid, int instanceId) {
    final List<int> bytes = List.from(uuid.toList())..add(instanceId);
    const equality = const ListEquality<int>();
    return equality.hash(bytes);
  }

  int get hashCode => _hashCode;

  operator ==(other) =>
      other is BluetoothCharacteristicIdentifier &&
      this.hashCode == other.hashCode;
}

class BluetoothCharacteristic {
  final BluetoothCharacteristicIdentifier id;
  final DeviceIdentifier deviceId;
  final Uuid serviceUuid; // The service that this characteristic belongs to.
  final Uuid
      secondaryServiceUuid; // The nested service that this characteristic belongs to.
  final CharacteristicProperties properties;
  final List<BluetoothDescriptor> descriptors;
  bool get isNotifying {
    try {
      var cccd =
          descriptors.singleWhere((d) => d.uuid == BluetoothDescriptor.cccd);
      return ((cccd.lastValue[0] & 0x01) > 0 || (cccd.lastValue[0] & 0x02) > 0);
    } catch (e) {
      return false;
    }
  }

  BehaviorSubject<List<int>> _value;
  Stream<List<int>> get value => Rx.merge([
        _value.stream,
        _onValueChangedStream,
      ]);

  List<int> get lastValue => _value.value;

  BluetoothCharacteristic.fromProto(protos.BluetoothCharacteristic p)
      : id = BluetoothCharacteristicIdentifier.fromProto(p.identifier),
        deviceId = new DeviceIdentifier(p.remoteId),
        serviceUuid = Uuid.fromString(p.serviceUuid),
        secondaryServiceUuid = (p.secondaryServiceUuid.length > 0)
            ? Uuid.fromString(p.secondaryServiceUuid)
            : null,
        descriptors = p.descriptors
            .map((d) => new BluetoothDescriptor.fromProto(d))
            .toList(),
        properties = new CharacteristicProperties.fromProto(p.properties),
        _value = BehaviorSubject.seeded(p.value);

  Stream<BluetoothCharacteristic> get _onCharacteristicChangedStream =>
      FlutterBlue.instance._methodStream
          .where((m) => m.method == "OnCharacteristicChanged")
          .map((m) => m.arguments)
          .map(
              (buffer) => new protos.OnCharacteristicChanged.fromBuffer(buffer))
          .where((p) => p.remoteId == deviceId.toString())
          .map((p) => new BluetoothCharacteristic.fromProto(p.characteristic))
          .where((c) => c.id == id)
          .map((c) {
        // Update the characteristic with the new values
        _updateDescriptors(c.descriptors);
//        _value.add(c.lastValue);
//        print('c.lastValue: ${c.lastValue}');
        return c;
      });

  Stream<List<int>> get _onValueChangedStream =>
      _onCharacteristicChangedStream.map((c) => c.lastValue);

  void _updateDescriptors(List<BluetoothDescriptor> newDescriptors) {
    for (var d in descriptors) {
      for (var newD in newDescriptors) {
        if (d.uuid == newD.uuid) {
          d._value.add(newD.lastValue);
        }
      }
    }
  }

  /// Retrieves the value of the characteristic
  Future<List<int>> read() async {
    var request = protos.ReadCharacteristicRequest.create()
      ..remoteId = deviceId.toString()
      ..characteristicId = id.toProto
      ..serviceUuid = serviceUuid.toString();
    FlutterBlue.instance._log(LogLevel.info,
        'remoteId: ${deviceId.toString()} characteristicUuid: ${id.uuid.toString()} serviceUuid: ${serviceUuid.toString()}');

    await FlutterBlue.instance._channel
        .invokeMethod('readCharacteristic', request.writeToBuffer());

    return FlutterBlue.instance._methodStream
        .where((m) => m.method == "ReadCharacteristicResponse")
        .map((m) => m.arguments)
        .map((buffer) =>
            new protos.ReadCharacteristicResponse.fromBuffer(buffer))
        .where((p) =>
            (p.remoteId == request.remoteId) &&
            (p.characteristic.identifier == request.characteristicId) &&
            (p.characteristic.serviceUuid == request.serviceUuid))
        .map((p) => p.characteristic.value)
        .first
        .then((d) {
      _value.add(d);
      return d;
    });
  }

  /// Writes the value of a characteristic.
  /// [CharacteristicWriteType.withoutResponse]: the write is not
  /// guaranteed and will return immediately with success.
  /// [CharacteristicWriteType.withResponse]: the method will return after the
  /// write operation has either passed or failed.
  Future<Null> write(List<int> value, {bool withoutResponse = false}) async {
    final type = withoutResponse
        ? CharacteristicWriteType.withoutResponse
        : CharacteristicWriteType.withResponse;

    var request = protos.WriteCharacteristicRequest.create()
      ..remoteId = deviceId.toString()
      ..characteristicId = id.toProto
      ..serviceUuid = serviceUuid.toString()
      ..writeType =
          protos.WriteCharacteristicRequest_WriteType.valueOf(type.index)
      ..value = value;

    var result = await FlutterBlue.instance._channel
        .invokeMethod('writeCharacteristic', request.writeToBuffer());

    if (type == CharacteristicWriteType.withoutResponse) {
      _value.add(value);
      return result;
    }

    return FlutterBlue.instance._methodStream
        .where((m) => m.method == "WriteCharacteristicResponse")
        .map((m) => m.arguments)
        .map((buffer) =>
            new protos.WriteCharacteristicResponse.fromBuffer(buffer))
        .where((p) =>
            (p.request.remoteId == request.remoteId) &&
            (p.request.characteristicId == request.characteristicId) &&
            (p.request.serviceUuid == request.serviceUuid))
        .first
        .then((w) => w.success)
        .then((success) => (!success)
            ? throw new Exception('Failed to write the characteristic')
            : null)
        .then((_) => _value.add(value))
        .then((_) => null);
  }

  /// Sets notifications or indications for the value of a specified characteristic
  Future<bool> setNotifyValue(bool notify) async {
    var request = protos.SetNotificationRequest.create()
      ..remoteId = deviceId.toString()
      ..serviceUuid = serviceUuid.toString()
      ..characteristicId = id.toProto
      ..enable = notify;

    await FlutterBlue.instance._channel
        .invokeMethod('setNotification', request.writeToBuffer());

    return FlutterBlue.instance._methodStream
        .where((m) => m.method == "SetNotificationResponse")
        .map((m) => m.arguments)
        .map((buffer) => new protos.SetNotificationResponse.fromBuffer(buffer))
        .where((p) =>
            (p.remoteId == request.remoteId) &&
            (p.characteristic.identifier == request.characteristicId) &&
            (p.characteristic.serviceUuid == request.serviceUuid))
        .first
        .then((p) => new BluetoothCharacteristic.fromProto(p.characteristic))
        .then((c) {
      _updateDescriptors(c.descriptors);
      _value.add(c.lastValue);
      return (c.isNotifying == notify);
    });
  }
}

enum CharacteristicWriteType { withResponse, withoutResponse }

@immutable
class CharacteristicProperties {
  final bool broadcast;
  final bool read;
  final bool writeWithoutResponse;
  final bool write;
  final bool notify;
  final bool indicate;
  final bool authenticatedSignedWrites;
  final bool extendedProperties;
  final bool notifyEncryptionRequired;
  final bool indicateEncryptionRequired;

  CharacteristicProperties(
      {this.broadcast = false,
      this.read = false,
      this.writeWithoutResponse = false,
      this.write = false,
      this.notify = false,
      this.indicate = false,
      this.authenticatedSignedWrites = false,
      this.extendedProperties = false,
      this.notifyEncryptionRequired = false,
      this.indicateEncryptionRequired = false});

  CharacteristicProperties.fromProto(protos.CharacteristicProperties p)
      : broadcast = p.broadcast,
        read = p.read,
        writeWithoutResponse = p.writeWithoutResponse,
        write = p.write,
        notify = p.notify,
        indicate = p.indicate,
        authenticatedSignedWrites = p.authenticatedSignedWrites,
        extendedProperties = p.extendedProperties,
        notifyEncryptionRequired = p.notifyEncryptionRequired,
        indicateEncryptionRequired = p.indicateEncryptionRequired;
}
