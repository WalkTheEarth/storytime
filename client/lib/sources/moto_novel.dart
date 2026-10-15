import 'dart:convert';
import 'dart:typed_data';

import 'package:asn1lib/asn1lib.dart';
import 'package:http/http.dart' as http;
import 'package:pointycastle/export.dart';

import '../core/models.dart';
import '../core/source.dart';

/// MotoNovel (com.motonovel.reader) — guest login with RSA/AES wrapped session,
/// SHA1WithRSA request signing with the per-user key.
/// See API.md §3.
class MotoNovelSource extends NovelSource {
  MotoNovelSource({http.Client? client}) : _client = client ?? http.Client();

  static const _base = 'https://motonovel-api.bkneng.com/oversea-';

  /// 1024-bit RSA public key embedded in libbkneng-jni.so. The server wraps the
  /// session AES key as a PKCS#1 v1.5 type-1 block "signed" with its private
  /// key; we recover it with a public-key modular operation.
  static const _loginPubDerB64 =
      'MIGfMA0GCSqGSIb3DQEBAQUAA4GNADCBiQKBgQClTsX4wJRr7xW7EKVUtSUg/K1f'
      'rM2UGUOUya6MQCXwl+hHXxyqnf03lPKOdF2tTKARGoFVuy1EDLHca47rrnxt4Sgt'
      'upzWy6W3sAda3Em5akn2onPkkUmPynnQD7ORW7N77frZ+cMX3eKhSx5njfiftD2C'
      'Wy6bYD57fXY8NXSCSQIDAQAB';

  final http.Client _client;
  static final _deviceId =
      'st${DateTime.now().millisecondsSinceEpoch.toRadixString(36)}';

  String? _username;
  String? _token;
  String? _userPrivB64; // base64 DER PKCS#8
  RSAPrivateKey? _userKey;

  @override
  String get id => 'moto_novel';

  @override
  String get name => 'MotoNovel';

  Map<String, String> _common() {
    final ts = '${DateTime.now().millisecondsSinceEpoch}';
    return {
      'n1': '1', 'n2': ts, 'n3': '1', 'n4': 'android',
      'n5': '1.4.8', 'n6': '1', 'n7': 'en', 'n8': 'US',
    };
  }

  /// Params AbsNetHelper.Y() admits into the signature source.
  static const _signWhitelist = {
    'username', 'device', 'timestamp', 'token', 'accessToken', 'page', 'size',
    'searchStr', 'bookId', 'chapterId', 'chapterName', 'paragraphId', 'type',
    'code', 'title', 'content', 'key', 'keys', 'level', 'state', 'count',
    'days', 'month', 'times', 'origin', 'platform', 'channel', 'channelId',
    'channels', 'topicId', 'talkId', 'productId', 'cardId', 'gearId',
    'seriesId', 'interestKeys', 'switchOn', 'modelType', 'indexType',
    'frequencyId', 'input', 'targetName', 'talkIds', 'positionX', 'positionY',
    'externJson', 'versionTag', 'ancestorId', 'parentId', 'address', 'aid',
    'autoCommit', 'value', 'extensionId', 'bid', 'id', 'chapterIds', 'bookIds',
  };

  Future<Map<String, dynamic>> _post(String path, Map<String, String> params) =>
      _call(path, params, method: 'POST');

  Future<Map<String, dynamic>> _get(String path, Map<String, String> params) =>
      _call(path, params, method: 'GET');

  Future<Map<String, dynamic>> _call(
    String path,
    Map<String, String> extra, {
    required String method,
  }) async {
    await _ensureLogin();
    final p = <String, String>{
      'username': _username!,
      'device': _deviceId,
      'timestamp': '${DateTime.now().millisecondsSinceEpoch}',
      'token': _token!,
      ..._common(),
      ...extra,
    };
    p['sign'] = _sign(p);

    final uri = Uri.parse('$_base$path');
    http.Response res;
    if (method == 'GET') {
      // download/* and user/* services read auth from the query string.
      res = await _client
          .get(uri.replace(queryParameters: p))
          .timeout(const Duration(seconds: 20));
    } else {
      res = await _client
          .post(uri,
              headers: const {'Content-Type': 'application/x-www-form-urlencoded'},
              body: p)
          .timeout(const Duration(seconds: 20));
    }
    if (res.statusCode == 401 || res.statusCode == 403) {
      // Session likely stale — retry once with a fresh login.
      _token = null;
      await _ensureLogin();
      return _call(path, extra, method: method);
    }
    final body = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
    if (body['code'] != 0) {
      throw SourceException('$name ${body['code']}: ${body['msg']}');
    }
    return body['data'] as Map<String, dynamic>? ?? const {};
  }

  /// SHA1WithRSA over sorted whitelisted params, made with the per-user key.
  String _sign(Map<String, String> params) {
    final keys = params.keys
        .where((k) => _signWhitelist.contains(k) && (params[k] ?? '').isNotEmpty)
        .toList()
      ..sort();
    final src = keys.map((k) => '$k=${params[k]}').join('&');
    // RSASigner performs PKCS#1 v1.5 encoding internally; '06052b0e03021a' is
    // the DER DigestInfo prefix OID for SHA-1.
    final signer = RSASigner(SHA1Digest(), '06052b0e03021a');
    signer.init(true, PrivateKeyParameter<RSAPrivateKey>(_userKey!));
    final sig = signer.generateSignature(Uint8List.fromList(utf8.encode(src)));
    return base64Encode(sig.bytes);
  }

  Future<void> _ensureLogin() async {
    if (_token != null && _userKey != null) return;

    final res = await _client
        .post(Uri.parse('${_base}user/out/login/guest'),
            headers: const {'Content-Type': 'application/x-www-form-urlencoded'},
            body: {'device': _deviceId, ..._common()})
        .timeout(const Duration(seconds: 20));
    final json = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
    if (json['code'] != 0) throw SourceException('$name login: ${json['msg']}');
    final data = json['data'] as Map<String, dynamic>;
    _username = data['userName'] as String;
    final inner = (data['data'] as Map<String, dynamic>?) ?? data;

    final aesKeyB64 = _recoverAesKeyB64(inner['aesKey'] as String);
    final session = _aesCbcDecrypt(inner['aesData'] as String, aesKeyB64);
    _token = session['token'] as String;
    _userPrivB64 = session['userPriKey'] as String;
    _userKey = _parsePkcs8Rsa(base64Decode(_userPrivB64!));
  }

  /// Recover the base64 AES key from the RSA type-1 block via public exponentiation.
  String _recoverAesKeyB64(String aesKeyB64) {
    final pubDer = base64Decode(_loginPubDerB64);
    final seq = ASN1Parser(pubDer).nextObject() as ASN1Sequence;
    final bitString = seq.elements[1] as ASN1BitString;
    final inner = ASN1Parser(Uint8List.fromList(bitString.stringValue))
        .nextObject() as ASN1Sequence;
    // RSAPublicKey ::= SEQUENCE { modulus INTEGER, publicExponent INTEGER }
    final modulus = (inner.elements[0] as ASN1Integer).valueAsBigInteger;

    final c = _bytesToBigInt(base64Decode(aesKeyB64));
    final m = c.modPow(BigInt.from(65537), modulus);
    final bytes = _bigIntToBytes(m, 128);
    // PKCS#1 v1.5 type 1: 00 01 FF...FF 00 <key>
    final sep = bytes.indexOf(0, 2);
    return ascii.decode(bytes.sublist(sep + 1));
  }

  static BigInt _bytesToBigInt(Uint8List bytes) {
    var v = BigInt.zero;
    for (final b in bytes) {
      v = (v << 8) | BigInt.from(b);
    }
    return v;
  }

  static Uint8List _bigIntToBytes(BigInt v, int len) {
    final out = Uint8List(len);
    for (var i = len - 1; i >= 0 && v > BigInt.zero; i--) {
      out[i] = (v & BigInt.from(0xff)).toInt();
      v >>= 8;
    }
    return out;
  }

  /// AES-128-CBC, key = base64decode(aesKeyB64), IV = key[:16], PKCS7.
  Map<String, dynamic> _aesCbcDecrypt(String ctB64, String aesKeyB64) {
    final key = base64Decode(aesKeyB64);
    final ct = base64Decode(ctB64);
    final params = ParametersWithIV(KeyParameter(key.sublist(0, 16)), key.sublist(0, 16));
    final dec = CBCBlockCipher(AESEngine())..init(false, params);
    final out = Uint8List(ct.length);
    for (var i = 0; i < ct.length; i += 16) {
      dec.processBlock(ct, i, out, i);
    }
    final pad = out[out.length - 1];
    final pt = out.sublist(0, out.length - pad);
    return jsonDecode(utf8.decode(pt)) as Map<String, dynamic>;
  }

  /// Parse a PKCS#8 (unencrypted) DER RSA private key.
  RSAPrivateKey _parsePkcs8Rsa(Uint8List der) {
    final top = ASN1Parser(der).nextObject() as ASN1Sequence;
    // PKCS#8: SEQUENCE { version INTEGER, AlgorithmIdentifier SEQUENCE,
    //                     OCTET STRING { RSAPrivateKey } }
    final octets = top.elements[2] as ASN1OctetString;
    final keySeq =
        ASN1Parser(Uint8List.fromList(octets.contentBytes())).nextObject() as ASN1Sequence;
    BigInt at(int i) => (keySeq.elements[i] as ASN1Integer).valueAsBigInteger;
    // PKCS#1 RSAPrivateKey: version, n, e, d, p, q, ... — pointycastle needs
    // (modulus, privateExponent, p, q).
    return RSAPrivateKey(at(1), at(3), at(4), at(5));
  }

  @override
  Future<SearchResult> search(String query, {int page = 1}) async {
    final data = await _post('opmcapi/out/search/indexV2', {
      'searchStr': query,
      'page': '$page',
      'size': '20',
    });
    final result = (data['result'] as List? ?? const []).cast<Map<String, dynamic>>();
    final books = result.map(_book).where((b) => b.id.isNotEmpty).toList();
    return SearchResult(books: books, hasMore: result.length >= 20);
  }

  /// Search hits are "extensions"; the numeric book id (bid) is encoded in
  /// extensionName as "BOOK[<bid>]-KOC[<n>]".
  Book _book(Map<String, dynamic> j) {
    final ext = (j['extensionName'] ?? '').toString();
    final bid = RegExp(r'BOOK\[(\d+)\]').firstMatch(ext)?.group(1) ??
        (j['bid'] ?? j['bookId'] ?? '').toString();
    return Book(
      sourceId: id,
      id: bid,
      title: (j['showName'] ?? j['name'] ?? '').toString(),
      coverUrl: j['picUrl']?.toString(),
      intro: j['description']?.toString(),
    );
  }

  @override
  Future<Book> book(String bookId) async {
    final data = await _post('opmcapi/out/book/front', {'bookId': bookId});
    return _book({...data, 'bid': bookId});
  }

  @override
  Future<List<Chapter>> chapters(String bookId) async {
    final data = await _post('opmcapi/out/book/catalogues', {'bookId': bookId});
    final contents = (data['contents'] as List? ?? const []).cast<Map<String, dynamic>>();
    return contents
        .map((c) => Chapter(
              sourceId: id,
              bookId: bookId,
              id: '${c['chapterId']}',
              title: (c['chapterName'] ?? 'Chapter ${c['chapterId']}').toString(),
              // feeType 1 = paid; guests can only read free/preview chapters.
              locked: c['feeType'] == 1,
              index: c['chapterId'] as int?,
            ))
        .toList();
  }

  @override
  Future<ChapterContent> chapterContent(Chapter chapter) async {
    final data = await _get('download/out/h5/chapter', {
      'bookId': chapter.bookId,
      'chapterId': chapter.id,
    });
    final text = (data['content'] ?? '').toString();
    return ChapterContent(
      title: (data['chapterName'] ?? chapter.title).toString(),
      paragraphs: const LineSplitter().convert(text),
    );
  }
}
