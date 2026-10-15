#!/usr/bin/env python3
"""MotoNovel full flow (verified live):

1. POST /oversea-user/out/login/guest  (form: device + n1..n8 common params)
   -> {data:{userName, data:{aesKey, aesData}}}
   - aesKey: base64 RSA blob = server-signed PKCS#1 v1.5 type-1 block; recover the
     base64 AES key by public-key operation (e=65537) with login_public.pem,
     then unpad after the first 0x00 byte.
   - aesData: AES-128-CBC, key = base64decode(aesKeyB64), IV = key[:16]
     -> JSON {token, userPriKey(PKCS#8 b64 DER)}

2. Authenticated calls: POST form with common params (username, device,
   timestamp, token, n1..n8) + endpoint params. `sign` = SHA1WithRSA over
   "k=v&k=v..." of the WHITELISTED params only (sorted by key), signed with
   userPriKey. Non-whitelist params (n*, page-numbers not in whitelist, etc.)
   are sent but not signed.
"""
import base64, json, sys, time, urllib.parse, urllib.request

from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import padding
from cryptography.hazmat.primitives.ciphers import Cipher, algorithms, modes

BASE = "https://motonovel-api.bkneng.com/oversea-"
DEVICE = "abc123deviceid456"

# params AbsNetHelper.Y() admits into the signature source (s3/f.java)
WHITELIST = {
    "username", "device", "timestamp", "token", "accessToken", "page", "size",
    "searchStr", "bookId", "chapterId", "chapterName", "paragraphId", "type",
    "code", "title", "content", "key", "keys", "level", "state", "count",
    "days", "month", "times", "origin", "platform", "channel", "channelId",
    "channels", "topicId", "talkId", "productId", "cardId", "gearId", "seriesId",
    "interestKeys", "switchOn", "modelType", "indexType", "frequencyId",
    "input", "targetName", "talkIds", "positionX", "positionY", "externJson",
    "versionTag", "ancestorId", "parentId", "address", "aid", "autoCommit",
    "value", "level", "extensionId", "bid", "id", "chapterIds", "bookIds",
}

LOGIN_PUB = serialization.load_pem_public_key(open("login_public.pem", "rb").read())


def post(path, data):
    body = urllib.parse.urlencode(data).encode()
    req = urllib.request.Request(BASE + path, data=body, method="POST")
    req.add_header("Content-Type", "application/x-www-form-urlencoded")
    try:
        with urllib.request.urlopen(req, timeout=30) as r:
            return json.loads(r.read().decode())
    except urllib.error.HTTPError as e:
        return {"_http": e.code, "_body": e.read().decode()[:200]}


def common():
    ts = str(int(time.time() * 1000))
    return {"n1": "1", "n2": ts, "n3": "1", "n4": "android",
            "n5": "1.4.8", "n6": "1", "n7": "en", "n8": "US"}


def login():
    resp = post("user/out/login/guest", {"device": DEVICE, **common()})
    d = resp["data"]
    uname = d.get("userName")
    d = d.get("data", d)
    # RSA public-op to recover the base64 AES key
    mb = pow(int.from_bytes(base64.b64decode(d["aesKey"]), "big"),
             65537, LOGIN_PUB.public_numbers().n).to_bytes(128, "big")
    aeskey_b64 = mb[mb.find(b"\x00", 2) + 1:].decode()
    key = base64.b64decode(aeskey_b64)
    dec = Cipher(algorithms.AES(key), modes.CBC(key[:16])).decryptor()
    pt = dec.update(base64.b64decode(d["aesData"])) + dec.finalize()
    pt = pt[:-pt[-1]]  # PKCS7
    sess = json.loads(pt.decode())
    return uname, sess["token"], sess["userPriKey"]


def signed_post(path, extra, uname, token, user_priv_b64):
    p = {"username": uname, "device": DEVICE,
         "timestamp": str(int(time.time() * 1000)), "token": token, **common()}
    p.update(extra)
    src = "&".join(f"{k}={p[k]}" for k in sorted(p)
                   if k in WHITELIST and p.get(k) not in ("", None))
    key = serialization.load_der_private_key(base64.b64decode(user_priv_b64),
                                             password=None)
    p["sign"] = base64.b64encode(
        key.sign(src.encode(), padding.PKCS1v15(), hashes.SHA1())).decode()
    return post(path, p)


def signed_get(path, extra, uname, token, user_priv_b64):
    """download/* services read auth from the query string via GET."""
    p = {"username": uname, "device": DEVICE,
         "timestamp": str(int(time.time() * 1000)), "token": token, **common()}
    p.update(extra)
    src = "&".join(f"{k}={p[k]}" for k in sorted(p)
                   if k in WHITELIST and p.get(k) not in ("", None))
    key = serialization.load_der_private_key(base64.b64decode(user_priv_b64),
                                             password=None)
    p["sign"] = base64.b64encode(
        key.sign(src.encode(), padding.PKCS1v15(), hashes.SHA1())).decode()
    url = BASE + path + "?" + urllib.parse.urlencode(p)
    req = urllib.request.Request(url, method="GET")
    try:
        with urllib.request.urlopen(req, timeout=30) as r:
            return json.loads(r.read().decode())
    except urllib.error.HTTPError as e:
        return {"_http": e.code, "_body": e.read().decode()[:200]}


if __name__ == "__main__":
    uname, token, user_priv = login()
    print("login ok:", uname, "token:", token)
    kw = sys.argv[1] if len(sys.argv) > 1 else "599002"
    r = signed_post("opmcapi/out/search/indexV2",
                    {"searchStr": kw, "page": "1", "size": "10"},
                    uname, token, user_priv)
    print(json.dumps(r, ensure_ascii=False)[:1500])
    # resolve story-code extension -> bid, catalogue, then chapter content
    WHITELIST.update({"extensionId", "bookId", "chapterId"})
    ext = r["data"]["result"][0]
    bid = ext.get("bid")
    print("bid:", bid)
    cat = signed_post("opmcapi/out/book/catalogues", {"bookId": bid},
                      uname, token, user_priv)
    ch = cat["data"]["contents"][0]
    print("chapter:", ch["chapterId"], ch["chapterName"])
    content = signed_get("download/out/h5/chapter",
                         {"bookId": bid, "chapterId": str(ch["chapterId"])},
                         uname, token, user_priv)
    print("content:", json.dumps(content, ensure_ascii=False)[:300])
