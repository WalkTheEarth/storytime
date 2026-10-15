#!/usr/bin/env python3
"""MotoNovel live API test — story code -> book -> chapter content.

Verified flow (documented in API.md):
  1. POST /oversea-user/out/login/guest          -> guest session
     - data.data.aesKey : base64 128-byte RSA "public op" block (server-signed,
       PKCS#1 v1.5 type-1, e=65537). Recover the base64 AES key by computing
       m = raw^e mod n with login_public.pem, then take bytes after the first
       0x00 that follows the 00 01 FF..FF header.
     - data.data.aesData: AES-128-CBC, key = b64decode(aesKeyB64), IV = key[:16]
       -> JSON {token, userPriKey(PKCS#8 b64 DER)}
  2. signed POST opmcapi/out/search/indexV2 {searchStr: <code>} -> result[]
     - story codes resolve as "extensions"; the bid is encoded in
       extensionName as "BOOK[<bid>]-KOC[<n>]".
  3. signed POST opmcapi/out/book/catalogues {bookId: bid} -> chapter list
  4. signed GET  download/out/h5/chapter {bookId, chapterId} -> chapter text

Every opmcapi call carries the common n1..n8 params plus username/device/
timestamp/token, and `sign` = Base64(SHA1WithRSA("k=v&k=v...")) over the
WHITELISTED params only, sorted by key, signed with userPriKey.

Usage: python3 test_moto_novel.py [story_code]   (default: 599002)
"""
import base64
import json
import re
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import padding
from cryptography.hazmat.primitives.ciphers import Cipher, algorithms, modes

BASE = "https://motonovel-api.bkneng.com/oversea-"
DEVICE = "abc123deviceid456"
APP = {"platform": "1", "os": "0", "appmode": "32", "deviceType": "2"}

# Params AbsNetHelper.Y() admits into the signature source (sources/s3/f.java)
WHITELIST = {
    "username", "device", "timestamp", "token", "accessToken", "page", "size",
    "searchStr", "bookId", "chapterId", "chapterName", "paragraphId", "type",
    "code", "title", "content", "key", "keys", "level", "state", "count",
    "days", "month", "times", "origin", "platform", "channel", "channelId",
    "channels", "topicId", "talkId", "productId", "cardId", "gearId", "seriesId",
    "interestKeys", "switchOn", "modelType", "indexType", "frequencyId",
    "input", "targetName", "talkIds", "positionX", "positionY", "externJson",
    "versionTag", "ancestorId", "parentId", "address", "aid", "autoCommit",
    "value", "extensionId", "bid", "id", "chapterIds", "bookIds",
}

_LOGIN_PUB = serialization.load_pem_public_key(
    open("login_public.pem", "rb").read())


def _http(url, data=None, method=None):
    req = urllib.request.Request(url, data=data, method=method)
    if data is not None:
        req.add_header("Content-Type", "application/x-www-form-urlencoded")
    try:
        with urllib.request.urlopen(req, timeout=30) as r:
            return r.status, json.loads(r.read().decode())
    except urllib.error.HTTPError as e:
        return e.code, {"_body": e.read().decode()[:200]}


def common():
    return {"n1": "1", "n2": str(int(time.time() * 1000)), "n3": "1",
            "n4": "android", "n5": "1.4.8", "n6": "1", "n7": "en", "n8": "US"}


def login():
    """Guest login -> (username, token, userPriKey_b64)."""
    body = urllib.parse.urlencode({"device": DEVICE, **common()}).encode()
    st, resp = _http(BASE + "user/out/login/guest", data=body)
    if st != 200:
        sys.exit(f"login failed: HTTP {st} {resp}")
    d = resp["data"]
    uname = d.get("userName")
    d = d.get("data", d)
    # RSA public operation on the server-signed block -> base64 AES key
    mb = pow(int.from_bytes(base64.b64decode(d["aesKey"]), "big"),
             65537, _LOGIN_PUB.public_numbers().n).to_bytes(128, "big")
    aeskey_b64 = mb[mb.find(b"\x00", 2) + 1:].decode()
    key = base64.b64decode(aeskey_b64)
    dec = Cipher(algorithms.AES(key), modes.CBC(key[:16])).decryptor()
    pt = dec.update(base64.b64decode(d["aesData"])) + dec.finalize()
    sess = json.loads(pt[:-pt[-1]].decode())  # strip PKCS7
    return uname, sess["token"], sess["userPriKey"]


def _signed_params(sess, extra):
    p = {"username": sess[0], "device": DEVICE,
         "timestamp": str(int(time.time() * 1000)), "token": sess[1],
         **common(), **APP}
    p.update(extra)
    src = "&".join(f"{k}={p[k]}" for k in sorted(p)
                   if k in WHITELIST and p.get(k) not in ("", None))
    key = serialization.load_der_private_key(
        base64.b64decode(sess[2]), password=None)
    p["sign"] = base64.b64encode(
        key.sign(src.encode(), padding.PKCS1v15(), hashes.SHA1())).decode()
    return p


def post(sess, path, extra):
    body = urllib.parse.urlencode(_signed_params(sess, extra)).encode()
    return _http(BASE + path, data=body)


def get(sess, path, extra):
    p = _signed_params(sess, extra)
    return _http(BASE + path + "?" + urllib.parse.urlencode(p), method="GET")


def main():
    code = sys.argv[1] if len(sys.argv) > 1 else "599002"
    print(f"== MotoNovel test, story code {code} ==")

    sess = login()
    print(f"1. guest login OK  user={sess[0]}  token={sess[1]}")

    st, r = post(sess, "opmcapi/out/search/indexV2",
                 {"searchStr": code, "page": "1", "size": "5"})
    if st != 200 or r.get("code") not in (0, "0", None):
        sys.exit(f"2. search failed: HTTP {st} {json.dumps(r)[:300]}")
    res = (r["data"].get("result") or [None])[0]
    if not res:
        sys.exit(f"2. no result for story code {code}")
    bid = re.search(r"BOOK\[(\d+)\]", res["extensionName"]).group(1)
    name = res.get("showName", "?")
    print(f"2. search OK  bid={bid}  name={name!r}  chapters={res.get('chapterNum')}")

    st, r = post(sess, "opmcapi/out/book/catalogues", {"bookId": str(bid)})
    if st != 200:
        sys.exit(f"3. catalogues failed: HTTP {st} {json.dumps(r)[:300]}")
    book = r["data"] or {}
    chapters = book.get("contents") or []
    print(f"3. catalogues OK  chapters={len(chapters)}"
          f"  (min={book.get('minChapterId')} max={book.get('maxChapterId')}"
          f" finish={book.get('isFinish')})")

    if not chapters:
        sys.exit("no chapters returned; raw: " + json.dumps(book)[:400])
    ch = chapters[0]
    cid = ch["chapterId"]
    title = ch.get("chapterName", "?")
    st, r = get(sess, "download/out/h5/chapter",
                {"bookId": str(bid), "chapterId": str(cid)})
    if st != 200 or r.get("code") not in (0, "0", None):
        sys.exit(f"4. chapter content failed: HTTP {st} {json.dumps(r)[:300]}")
    data = r.get("data") or {}
    text = data.get("content", "")
    print(f"4. content OK  chapterId={cid} title={title!r}  {len(text)} chars")
    print("-" * 60)
    print(text[:400])
    print("-" * 60)
    print("MotoNovel: SUCCESS — story code -> book -> content verified")


if __name__ == "__main__":
    main()
