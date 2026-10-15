// Debug: replicate MotoNovelSource._recoverAesKeyB64 + _aesCbcDecrypt on a
// live login response, byte-for-byte, to find where the Dart result diverges
// from the verified Python flow (work/moto/test_moto_novel.py).
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:asn1lib/asn1lib.dart';
import 'package:pointycastle/export.dart';

const _loginPubDerB64 =
    'MIGfMA0GCSqGSIb3DQEBAQUAA4GNADCBiQKBgQClTsX4wJRr7xW7EKVUtSUg/K1f'
    'rM2UGUOUya6MQCXwl+hHXxyqnf03lPKOdF2tTKARGoFVuy1EDLHca47rrnxt4Sgt'
    'upzWy6W3sAda3Em5akn2onPkkUmPynnQD7ORW7N77frZ+cMX3eKhSx5njfiftD2C'
    'Wy6bYD57fXY8NXSCSQIDAQAB';

BigInt _bytesToBigInt(Uint8List bytes) {
  var v = BigInt.zero;
  for (final b in bytes) {
    v = (v << 8) | BigInt.from(b);
  }
  return v;
}

Uint8List _bigIntToBytes(BigInt v, int len) {
  final out = Uint8List(len);
  for (var i = len - 1; i >= 0 && v > BigInt.zero; i--) {
    out[i] = (v & BigInt.from(0xff)).toInt();
    v >>= 8;
  }
  return out;
}

void main() async {
  final req = await HttpClient().postUrl(Uri.parse(
      'https://motonovel-api.bkneng.com/oversea-user/out/login/guest'));
  req.headers.contentType =
      ContentType('application', 'x-www-form-urlencoded');
  req.write(Uri.encodeQueryComponent('device').replaceAll('+', '%20'));
  final ts = '${DateTime.now().millisecondsSinceEpoch}';
  final body = 'device=abc123deviceid456&n1=1&n2=$ts&n3=1&n4=android'
      '&n5=1.4.8&n6=1&n7=en&n8=US';
  final req2 = await HttpClient().postUrl(Uri.parse(
      'https://motonovel-api.bkneng.com/oversea-user/out/login/guest'));
  req2.headers.contentType =
      ContentType('application', 'x-www-form-urlencoded');
  req2.write(body);
  final resp = await req2.close();
  final json = jsonDecode(await resp.transform(utf8.decoder).join())
      as Map<String, dynamic>;
  final data = json['data'] as Map<String, dynamic>;
  final inner = (data['data'] as Map<String, dynamic>?) ?? data;

  final aesKeyB64Blob = inner['aesKey'] as String;
  final ct = base64Decode(aesKeyB64Blob);
  print('aesKey blob: ${ct.length} bytes');

  final pubDer = base64Decode(_loginPubDerB64);
  final seq = ASN1Parser(pubDer).nextObject() as ASN1Sequence;
  print('spki elements: ${seq.elements.length}');
  final bitString = seq.elements[1] as ASN1BitString;
  final bitBytes = Uint8List.fromList(bitString.stringValue);
  print('bitString first bytes: ${bitBytes.take(6).toList()}');
  final innerSeq =
      ASN1Parser(bitBytes).nextObject() as ASN1Sequence;
  final modulus = (innerSeq.elements[0] as ASN1Integer).valueAsBigInteger;
  print('modulus bits: ${modulus.bitLength}');

  final c = _bytesToBigInt(ct);
  final m = c.modPow(BigInt.from(65537), modulus);
  final bytes = _bigIntToBytes(m, 128);
  print('m hex head: ${bytes.take(8).map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ')}');
  final sep = bytes.indexOf(0, 2);
  print('sep at: $sep');
  final keyB64 = ascii.decode(bytes.sublist(sep + 1));
  print('aes key b64: $keyB64');

  final key = base64Decode(keyB64);
  final ct2 = base64Decode(inner['aesData'] as String);
  final params =
      ParametersWithIV(KeyParameter(key.sublist(0, 16)), key.sublist(0, 16));
  final dec = CBCBlockCipher(AESEngine())..init(false, params);
  final out = Uint8List(ct2.length);
  for (var i = 0; i < ct2.length; i += 16) {
    dec.processBlock(ct2, i, out, i);
  }
  final pad = out[out.length - 1];
  final pt = out.sublist(0, out.length - pad);
  print('session: ${utf8.decode(pt)}');
}
