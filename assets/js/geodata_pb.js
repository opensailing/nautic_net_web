// source: geodata.proto
/**
 * @fileoverview
 * @enhanceable
 * @suppress {missingRequire} reports error on implicit type usages.
 * @suppress {messageConventions} JS Compiler reports an error if a variable or
 *     field starts with 'MSG_' and isn't a translatable message.
 * @public
 */
// GENERATED CODE -- DO NOT EDIT!
/* eslint-disable */
// @ts-nocheck

var jspb = require('google-protobuf');
var goog = jspb;
var global = (function() { return this || window || global || self || Function('return this')(); }).call(null);

goog.exportSymbol('proto.geodata.Current', null, global);
goog.exportSymbol('proto.geodata.GeoData', null, global);
/**
 * Generated by JsPbCodeGenerator.
 * @param {Array=} opt_data Optional initial data array, typically from a
 * server response, or constructed directly in Javascript. The array is used
 * in place and becomes part of the constructed object. It is not cloned.
 * If no data is provided, the constructed object will be empty, but still
 * valid.
 * @extends {jspb.Message}
 * @constructor
 */
proto.geodata.Current = function(opt_data) {
  jspb.Message.initialize(this, opt_data, 0, -1, null, null);
};
goog.inherits(proto.geodata.Current, jspb.Message);
if (goog.DEBUG && !COMPILED) {
  /**
   * @public
   * @override
   */
  proto.geodata.Current.displayName = 'proto.geodata.Current';
}
/**
 * Generated by JsPbCodeGenerator.
 * @param {Array=} opt_data Optional initial data array, typically from a
 * server response, or constructed directly in Javascript. The array is used
 * in place and becomes part of the constructed object. It is not cloned.
 * If no data is provided, the constructed object will be empty, but still
 * valid.
 * @extends {jspb.Message}
 * @constructor
 */
proto.geodata.GeoData = function(opt_data) {
  jspb.Message.initialize(this, opt_data, 0, -1, proto.geodata.GeoData.repeatedFields_, null);
};
goog.inherits(proto.geodata.GeoData, jspb.Message);
if (goog.DEBUG && !COMPILED) {
  /**
   * @public
   * @override
   */
  proto.geodata.GeoData.displayName = 'proto.geodata.GeoData';
}



if (jspb.Message.GENERATE_TO_OBJECT) {
/**
 * Creates an object representation of this proto.
 * Field names that are reserved in JavaScript and will be renamed to pb_name.
 * Optional fields that are not set will be set to undefined.
 * To access a reserved field use, foo.pb_<name>, eg, foo.pb_default.
 * For the list of reserved names please see:
 *     net/proto2/compiler/js/internal/generator.cc#kKeyword.
 * @param {boolean=} opt_includeInstance Deprecated. whether to include the
 *     JSPB instance for transitional soy proto support:
 *     http://goto/soy-param-migration
 * @return {!Object}
 */
proto.geodata.Current.prototype.toObject = function(opt_includeInstance) {
  return proto.geodata.Current.toObject(opt_includeInstance, this);
};


/**
 * Static version of the {@see toObject} method.
 * @param {boolean|undefined} includeInstance Deprecated. Whether to include
 *     the JSPB instance for transitional soy proto support:
 *     http://goto/soy-param-migration
 * @param {!proto.geodata.Current} msg The msg instance to transform.
 * @return {!Object}
 * @suppress {unusedLocalVariables} f is only used for nested messages
 */
proto.geodata.Current.toObject = function(includeInstance, msg) {
  var f, obj = {
    lat: jspb.Message.getFloatingPointFieldWithDefault(msg, 1, 0.0),
    lon: jspb.Message.getFloatingPointFieldWithDefault(msg, 2, 0.0),
    speed: jspb.Message.getFloatingPointFieldWithDefault(msg, 3, 0.0),
    direction: jspb.Message.getFloatingPointFieldWithDefault(msg, 4, 0.0)
  };

  if (includeInstance) {
    obj.$jspbMessageInstance = msg;
  }
  return obj;
};
}


/**
 * Deserializes binary data (in protobuf wire format).
 * @param {jspb.ByteSource} bytes The bytes to deserialize.
 * @return {!proto.geodata.Current}
 */
proto.geodata.Current.deserializeBinary = function(bytes) {
  var reader = new jspb.BinaryReader(bytes);
  var msg = new proto.geodata.Current;
  return proto.geodata.Current.deserializeBinaryFromReader(msg, reader);
};


/**
 * Deserializes binary data (in protobuf wire format) from the
 * given reader into the given message object.
 * @param {!proto.geodata.Current} msg The message object to deserialize into.
 * @param {!jspb.BinaryReader} reader The BinaryReader to use.
 * @return {!proto.geodata.Current}
 */
proto.geodata.Current.deserializeBinaryFromReader = function(msg, reader) {
  while (reader.nextField()) {
    if (reader.isEndGroup()) {
      break;
    }
    var field = reader.getFieldNumber();
    switch (field) {
    case 1:
      var value = /** @type {number} */ (reader.readFloat());
      msg.setLat(value);
      break;
    case 2:
      var value = /** @type {number} */ (reader.readFloat());
      msg.setLon(value);
      break;
    case 3:
      var value = /** @type {number} */ (reader.readFloat());
      msg.setSpeed(value);
      break;
    case 4:
      var value = /** @type {number} */ (reader.readFloat());
      msg.setDirection(value);
      break;
    default:
      reader.skipField();
      break;
    }
  }
  return msg;
};


/**
 * Serializes the message to binary data (in protobuf wire format).
 * @return {!Uint8Array}
 */
proto.geodata.Current.prototype.serializeBinary = function() {
  var writer = new jspb.BinaryWriter();
  proto.geodata.Current.serializeBinaryToWriter(this, writer);
  return writer.getResultBuffer();
};


/**
 * Serializes the given message to binary data (in protobuf wire
 * format), writing to the given BinaryWriter.
 * @param {!proto.geodata.Current} message
 * @param {!jspb.BinaryWriter} writer
 * @suppress {unusedLocalVariables} f is only used for nested messages
 */
proto.geodata.Current.serializeBinaryToWriter = function(message, writer) {
  var f = undefined;
  f = message.getLat();
  if (f !== 0.0) {
    writer.writeFloat(
      1,
      f
    );
  }
  f = message.getLon();
  if (f !== 0.0) {
    writer.writeFloat(
      2,
      f
    );
  }
  f = message.getSpeed();
  if (f !== 0.0) {
    writer.writeFloat(
      3,
      f
    );
  }
  f = message.getDirection();
  if (f !== 0.0) {
    writer.writeFloat(
      4,
      f
    );
  }
};


/**
 * optional float lat = 1;
 * @return {number}
 */
proto.geodata.Current.prototype.getLat = function() {
  return /** @type {number} */ (jspb.Message.getFloatingPointFieldWithDefault(this, 1, 0.0));
};


/**
 * @param {number} value
 * @return {!proto.geodata.Current} returns this
 */
proto.geodata.Current.prototype.setLat = function(value) {
  return jspb.Message.setProto3FloatField(this, 1, value);
};


/**
 * optional float lon = 2;
 * @return {number}
 */
proto.geodata.Current.prototype.getLon = function() {
  return /** @type {number} */ (jspb.Message.getFloatingPointFieldWithDefault(this, 2, 0.0));
};


/**
 * @param {number} value
 * @return {!proto.geodata.Current} returns this
 */
proto.geodata.Current.prototype.setLon = function(value) {
  return jspb.Message.setProto3FloatField(this, 2, value);
};


/**
 * optional float speed = 3;
 * @return {number}
 */
proto.geodata.Current.prototype.getSpeed = function() {
  return /** @type {number} */ (jspb.Message.getFloatingPointFieldWithDefault(this, 3, 0.0));
};


/**
 * @param {number} value
 * @return {!proto.geodata.Current} returns this
 */
proto.geodata.Current.prototype.setSpeed = function(value) {
  return jspb.Message.setProto3FloatField(this, 3, value);
};


/**
 * optional float direction = 4;
 * @return {number}
 */
proto.geodata.Current.prototype.getDirection = function() {
  return /** @type {number} */ (jspb.Message.getFloatingPointFieldWithDefault(this, 4, 0.0));
};


/**
 * @param {number} value
 * @return {!proto.geodata.Current} returns this
 */
proto.geodata.Current.prototype.setDirection = function(value) {
  return jspb.Message.setProto3FloatField(this, 4, value);
};



/**
 * List of repeated fields within this message type.
 * @private {!Array<number>}
 * @const
 */
proto.geodata.GeoData.repeatedFields_ = [1];



if (jspb.Message.GENERATE_TO_OBJECT) {
/**
 * Creates an object representation of this proto.
 * Field names that are reserved in JavaScript and will be renamed to pb_name.
 * Optional fields that are not set will be set to undefined.
 * To access a reserved field use, foo.pb_<name>, eg, foo.pb_default.
 * For the list of reserved names please see:
 *     net/proto2/compiler/js/internal/generator.cc#kKeyword.
 * @param {boolean=} opt_includeInstance Deprecated. whether to include the
 *     JSPB instance for transitional soy proto support:
 *     http://goto/soy-param-migration
 * @return {!Object}
 */
proto.geodata.GeoData.prototype.toObject = function(opt_includeInstance) {
  return proto.geodata.GeoData.toObject(opt_includeInstance, this);
};


/**
 * Static version of the {@see toObject} method.
 * @param {boolean|undefined} includeInstance Deprecated. Whether to include
 *     the JSPB instance for transitional soy proto support:
 *     http://goto/soy-param-migration
 * @param {!proto.geodata.GeoData} msg The msg instance to transform.
 * @return {!Object}
 * @suppress {unusedLocalVariables} f is only used for nested messages
 */
proto.geodata.GeoData.toObject = function(includeInstance, msg) {
  var f, obj = {
    currentsList: jspb.Message.toObjectList(msg.getCurrentsList(),
    proto.geodata.Current.toObject, includeInstance)
  };

  if (includeInstance) {
    obj.$jspbMessageInstance = msg;
  }
  return obj;
};
}


/**
 * Deserializes binary data (in protobuf wire format).
 * @param {jspb.ByteSource} bytes The bytes to deserialize.
 * @return {!proto.geodata.GeoData}
 */
proto.geodata.GeoData.deserializeBinary = function(bytes) {
  var reader = new jspb.BinaryReader(bytes);
  var msg = new proto.geodata.GeoData;
  return proto.geodata.GeoData.deserializeBinaryFromReader(msg, reader);
};


/**
 * Deserializes binary data (in protobuf wire format) from the
 * given reader into the given message object.
 * @param {!proto.geodata.GeoData} msg The message object to deserialize into.
 * @param {!jspb.BinaryReader} reader The BinaryReader to use.
 * @return {!proto.geodata.GeoData}
 */
proto.geodata.GeoData.deserializeBinaryFromReader = function(msg, reader) {
  while (reader.nextField()) {
    if (reader.isEndGroup()) {
      break;
    }
    var field = reader.getFieldNumber();
    switch (field) {
    case 1:
      var value = new proto.geodata.Current;
      reader.readMessage(value,proto.geodata.Current.deserializeBinaryFromReader);
      msg.addCurrents(value);
      break;
    default:
      reader.skipField();
      break;
    }
  }
  return msg;
};


/**
 * Serializes the message to binary data (in protobuf wire format).
 * @return {!Uint8Array}
 */
proto.geodata.GeoData.prototype.serializeBinary = function() {
  var writer = new jspb.BinaryWriter();
  proto.geodata.GeoData.serializeBinaryToWriter(this, writer);
  return writer.getResultBuffer();
};


/**
 * Serializes the given message to binary data (in protobuf wire
 * format), writing to the given BinaryWriter.
 * @param {!proto.geodata.GeoData} message
 * @param {!jspb.BinaryWriter} writer
 * @suppress {unusedLocalVariables} f is only used for nested messages
 */
proto.geodata.GeoData.serializeBinaryToWriter = function(message, writer) {
  var f = undefined;
  f = message.getCurrentsList();
  if (f.length > 0) {
    writer.writeRepeatedMessage(
      1,
      f,
      proto.geodata.Current.serializeBinaryToWriter
    );
  }
};


/**
 * repeated Current currents = 1;
 * @return {!Array<!proto.geodata.Current>}
 */
proto.geodata.GeoData.prototype.getCurrentsList = function() {
  return /** @type{!Array<!proto.geodata.Current>} */ (
    jspb.Message.getRepeatedWrapperField(this, proto.geodata.Current, 1));
};


/**
 * @param {!Array<!proto.geodata.Current>} value
 * @return {!proto.geodata.GeoData} returns this
*/
proto.geodata.GeoData.prototype.setCurrentsList = function(value) {
  return jspb.Message.setRepeatedWrapperField(this, 1, value);
};


/**
 * @param {!proto.geodata.Current=} opt_value
 * @param {number=} opt_index
 * @return {!proto.geodata.Current}
 */
proto.geodata.GeoData.prototype.addCurrents = function(opt_value, opt_index) {
  return jspb.Message.addToRepeatedWrapperField(this, 1, opt_value, proto.geodata.Current, opt_index);
};


/**
 * Clears the list making it empty but non-null.
 * @return {!proto.geodata.GeoData} returns this
 */
proto.geodata.GeoData.prototype.clearCurrentsList = function() {
  return this.setCurrentsList([]);
};


goog.object.extend(exports, proto.geodata);
